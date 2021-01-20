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
import os
from typing import cast

import boto3
from chalice import BadRequestError, Chalice, ForbiddenError
from chalice.app import Request

app = Chalice(app_name='scale_out_runner')

INTERESTED_REPOS = os.getenv('REPOS', 'apache/airflow').split(',')
ASG_GROUP_NAME = os.getenv('ASG_NAME', 'AshbRunnerASG')


_commiters = set()
GH_WEBHOOK_TOKEN = None


@app.route('/', methods=['POST'])
def index():
    validate_gh_sig(app.current_request)

    if app.current_request.headers.get('X-GitHub-Event', None) != "check_run":
        # Ignore things about installs/permissions etc
        return {'ignored': 'not about check_runs'}

    body = app.current_request.json_body

    repo = body['repository']['full_name']

    # Other repos configured with this app, but we don't do anything with them
    # yet.
    if repo not in INTERESTED_REPOS:
        app.log.debug("Ignoring event for %r", repo)
        return {'ignored': 'Other repo'}

    if body['action'] != 'created':
        return {'ignored': "action is not 'created'"}

    if body['check_run']['status'] != 'queued':
        # Skipped runs are "created", but are instantly completed. Ignore anything that is not queued
        return {'ignored': "check_run.status is not 'queued'"}

    sender = body['sender']['login']

    # use_self_hosted = sender in commiters()
    # XXX: HACK
    use_self_hosted = sender in ("ashb",)

    # Send the request to SQS. We don't actually need this json blob, just _a message_.
    send_to_sqs(body)

    payload = {'sender': sender, 'use_self_hosted': use_self_hosted}
    if use_self_hosted:
        payload.update(**scale_asg_if_needed())
    app.log.info("%r", payload)
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
    if not sig.startswith('sha256='):
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


def send_to_sqs(payload: dict):
    sqs = boto3.client('sqs')

    sqs.send_message(
        QueueUrl=os.getenv('ACTIONS_SQS_URL'),
        MessageBody=json.dumps(payload),
    )


def scale_asg_if_needed() -> dict:
    sqs = boto3.client('sqs')
    asg = boto3.client('autoscaling')

    attrs = sqs.get_queue_attributes(
        QueueUrl=os.getenv('ACTIONS_SQS_URL'), AttributeNames=['ApproximateNumberOfMessages']
    )

    backlog = int(attrs['Attributes']['ApproximateNumberOfMessages'])

    resp = asg.describe_auto_scaling_groups(
        AutoScalingGroupNames=[ASG_GROUP_NAME],
    )

    asg_info = resp['AutoScalingGroups'][0]

    desired = asg_info['DesiredCapacity']
    max_size = asg_info['MaxSize']

    busy = 0
    for instance in asg_info['Instances']:
        if instance['LifecycleState'] == 'InService' and instance['ProtectedFromScaleIn']:
            busy += 1

    new_size = backlog + busy
    if new_size != desired:
        if desired < max_size:
            try:
                asg.set_desired_capacity(AutoScalingGroupName=ASG_GROUP_NAME, DesiredCapacity=new_size)
                return {'new capcity': new_size}
            except asg.exceptions.ScalingActivityInProgressFault as e:
                return {'error': str(e)}
        else:
            return {'capcity_at_max': True}
    else:
        return {'idle_instances': True}
