# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

import codecs
import hmac
import json
import logging
import os
from typing import cast

import boto3
from chalice import BadRequestError, Chalice, ForbiddenError
from chalice.app import Request

app = Chalice(app_name='scale_out_runner')
app.log.setLevel(logging.INFO)

ASG_GROUP_NAME = os.getenv('ASG_NAME', 'AshbRunnerASG')
ASG_REGION_NAME = os.getenv('ASG_REGION_NAME', None)
TABLE_NAME = os.getenv('COUNTER_TABLE', 'GithubRunnerQueue')
_commiters = set()
GH_WEBHOOK_TOKEN = None

REPOS = os.getenv('REPOS')
if REPOS:
    REPO_CONFIGURATION = json.loads(REPOS)
else:
    REPO_CONFIGURATION = {
        # <repo>: [list-of-branches-to-use-self-hosted-on]
        'apache/airflow': {'main', 'master'},
    }
del REPOS


@app.route('/', methods=['POST'])
def index():
    validate_gh_sig(app.current_request)

    if app.current_request.headers.get('X-GitHub-Event', None) != "check_run":
        # Ignore things about installs/permissions etc
        return {'ignored': 'not about check_runs'}

    body = app.current_request.json_body

    repo = body['repository']['full_name']

    sender = body['sender']['login']

    # Other repos configured with this app, but we don't do anything with them
    # yet.
    if repo not in REPO_CONFIGURATION:
        app.log.info("Ignoring event for %r", repo)
        return {'ignored': 'Other repo'}

    interested_branches = REPO_CONFIGURATION[repo]

    branch = body['check_run']['check_suite']['head_branch']

    use_self_hosted = sender in commiters() or branch in interested_branches
    payload = {'sender': sender, 'use_self_hosted': use_self_hosted}

    if body['action'] == 'completed' and body['check_run']['conclusion'] == 'cancelled':
        if use_self_hosted:
            # The only time we get a "cancelled" job is when it wasn't yet running.
            queue_length = increment_dynamodb_counter(-1)
            # Don't scale in the ASG -- let the CloudWatch alarm do that.
            payload['new_queue'] = queue_length
        else:
            payload = {'ignored': 'unknown sender'}

    elif body['action'] != 'created':
        payload = {'ignored': "action is not 'created'"}

    elif body['check_run']['status'] != 'queued':
        # Skipped runs are "created", but are instantly completed. Ignore anything that is not queued
        payload = {'ignored': "check_run.status is not 'queued'"}
    else:
        if use_self_hosted:
            # Increment counter in DynamoDB
            queue_length = increment_dynamodb_counter()
            payload.update(**scale_asg_if_needed(queue_length))
    app.log.info(
        "delivery=%s branch=%s: %r",
        app.current_request.headers.get('X-GitHub-Delivery', None),
        branch,
        payload,
    )
    return payload


def commiters(ssm_repo_name: str = os.getenv('SSM_REPO_NAME', 'apache/airflow')):
    global _commiters

    if not _commiters:
        client = boto3.client('ssm')
        param_path = os.path.join('/runners/', ssm_repo_name, 'configOverlay')
        app.log.info("Loading config overlay from %s", param_path)

        try:

            resp = client.get_parameter(Name=param_path, WithDecryption=True)
        except client.exceptions.ParameterNotFound:
            app.log.debug("Failed to load config overlay", exc_info=True)
            return set()

        try:
            overlay = json.loads(resp['Parameter']['Value'])
        except ValueError:
            app.log.debug("Failed to parse config overlay", exc_info=True)
            return set()

        _commiters = set(overlay['pullRequestSecurity']['allowedAuthors'])

    return _commiters


def validate_gh_sig(request: Request):
    sig = request.headers.get('X-Hub-Signature-256', None)
    if not sig or not sig.startswith('sha256='):
        raise BadRequestError('X-Hub-Signature-256 not of expected format')

    sig = sig[len('sha256=') :]
    calculated_sig = sign_request_body(request)

    app.log.debug('Checksum verification - expected %s got %s', calculated_sig, sig)

    if not hmac.compare_digest(sig, calculated_sig):
        raise ForbiddenError('Spoofed request')


def sign_request_body(request: Request) -> str:
    global GH_WEBHOOK_TOKEN
    if GH_WEBHOOK_TOKEN is None:
        if 'GH_WEBHOOK_TOKEN' in os.environ:
            # Local dev support:
            GH_WEBHOOK_TOKEN = os.environ['GH_WEBHOOK_TOKEN'].encode('utf-8')
        else:
            encrypted = os.environb[b'GH_WEBHOOK_TOKEN_ENCRYPTED']

            kms = boto3.client('kms')
            response = kms.decrypt(CiphertextBlob=codecs.decode(encrypted, 'base64'))
            GH_WEBHOOK_TOKEN = response['Plaintext']
    body = cast(bytes, request.raw_body)
    return hmac.new(GH_WEBHOOK_TOKEN, body, digestmod='SHA256').hexdigest()  # type: ignore


def increment_dynamodb_counter(delta: int = 1) -> int:
    dynamodb = boto3.client('dynamodb')
    args = dict(
        TableName=TABLE_NAME,
        Key={'id': {'S': 'queued_jobs'}},
        ExpressionAttributeValues={':delta': {'N': str(delta)}},
        UpdateExpression='ADD queued :delta',
        ReturnValues='UPDATED_NEW',
    )

    if delta < 0:
        # Make sure it never goes below zero!
        args['ExpressionAttributeValues'][':limit'] = {'N': str(-delta)}
        args['ConditionExpression'] = 'queued >= :limit'

    resp = dynamodb.update_item(**args)
    return int(resp['Attributes']['queued']['N'])


def scale_asg_if_needed(num_queued_jobs: int) -> dict:
    asg = boto3.client('autoscaling', region_name=ASG_REGION_NAME)

    resp = asg.describe_auto_scaling_groups(
        AutoScalingGroupNames=[ASG_GROUP_NAME],
    )

    asg_info = resp['AutoScalingGroups'][0]

    current = asg_info['DesiredCapacity']
    max_size = asg_info['MaxSize']

    busy = 0
    for instance in asg_info['Instances']:
        if instance['LifecycleState'] == 'InService' and instance['ProtectedFromScaleIn']:
            busy += 1
    app.log.info("Busy instances: %d, num_queued_jobs: %d, current_size: %d", busy, num_queued_jobs, current)

    new_size = num_queued_jobs + busy
    if new_size > current:
        if new_size <= max_size or current < max_size:
            try:
                new_size = min(new_size, max_size)
                asg.set_desired_capacity(AutoScalingGroupName=ASG_GROUP_NAME, DesiredCapacity=new_size)
                return {'new_capcity': new_size}
            except asg.exceptions.ScalingActivityInProgressFault as e:
                return {'error': str(e)}
        else:
            return {'capacity_at_max': True}
    else:
        return {'idle_instances': True}
