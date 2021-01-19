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

import hmac
import json
import os
from typing import cast

import boto3
import pendulum
from chalice import BadRequestError, Chalice, ForbiddenError
from chalice.app import Request

app = Chalice(app_name='scale_out_runner')

INTERESTED_REPOS = os.getenv('REPOS', 'apache/airflow').split(',')
ASG_GROUP_NAME = os.getenv('ASG_NAME', 'AshbRunnerASG')


_commiters = set()


@app.route('/', methods=['POST'])
def index():
    validate_gh_sig(app.current_request)

    body = app.current_request.json_body

    repo = body['repository']['full_name']

    # Other repos configured with this app, but we don't do anything with them
    # yet.
    if repo not in INTERESTED_REPOS:
        app.log.debug("Ignoring event for %r", repo)
        return {'ignored': 'Other repo'}

    sender = body['sender']['login']

    use_self_hosted = sender in commiters()

    payload = {'sender': sender, 'use_self_hosted': use_self_hosted}
    if use_self_hosted:
        if has_idle_instances():
            payload['idle_instances'] = True
        else:
            payload['scaled_out'] = scale_out_runner_asg()
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
    sig = request.headers['X-Hub-Signature-256']
    if not sig.startswith('sha256='):
        raise BadRequestError('X-Hub-Signature-256 not of expected format')

    sig = sig[len('sha256=') :]
    calculated_sig = sign_request_body(request)

    app.log.debug('Checksum verification - expected %s got %s', calculated_sig, sig)

    if not hmac.compare_digest(sig, calculated_sig):
        raise ForbiddenError('Spoofed request')


def sign_request_body(request: Request) -> str:
    key = os.environ['GH_WEBHOOK_TOKEN'].encode('utf-8')
    body = cast(bytes, request.raw_body)
    return hmac.new(key, body, digestmod='SHA256').hexdigest()  # type: ignore


def has_idle_instances():
    client = boto3.client('cloudwatch')

    end_time = pendulum.now().start_of('minute')
    start_time = end_time.subtract(minutes=1)

    resp = client.get_metric_data(
        StartTime=start_time,
        EndTime=end_time,
        MaxDatapoints=1,
        # This is likely far from perfect, as it only looks at the snapshot reported a minute ago.
        MetricDataQueries=[
            {"Id": "e1", "Expression": "m2 - m1", "Label": "Idle instances", "ReturnData": True},
            {
                "Id": "m2",
                "MetricStat": {
                    "Metric": {
                        "Namespace": "AWS/AutoScaling",
                        "MetricName": "GroupInServiceInstances",
                        "Dimensions": [
                            {
                                "Name": "AutoScalingGroupName",
                                "Value": ASG_GROUP_NAME,
                            }
                        ],
                    },
                    "Period": 60,
                    "Stat": "Average",
                },
                "ReturnData": False,
            },
            {
                "Id": "m1",
                "MetricStat": {
                    "Metric": {"Namespace": "github.actions", "MetricName": "jobs-running", "Dimensions": []},
                    "Period": 60,
                    "Stat": "Sum",
                },
                "ReturnData": False,
            },
        ],
    )

    idle_instances: float = resp['MetricDataResults'][0]['Values'][0]

    return idle_instances > 0


def scale_out_runner_asg():
    asg = boto3.client('autoscaling')

    resp = asg.describe_auto_scaling_groups(
        AutoScalingGroupNames=[ASG_GROUP_NAME],
    )

    group = resp['AutoScalingGroups'][0]

    desired = group['DesiredCapacity']
    max_size = group['MaxSize']

    try:
        if desired < max_size:
            asg.set_desired_capacity(AutoScalingGroupName=ASG_GROUP_NAME, DesiredCapacity=desired + 1)
            return {'new capcity': desired + 1}
        else:
            return {'capcity_at_max': True}
    except asg.exceptions.ScalingActivityInProgressFault as e:
        return {'error': str(e)}
