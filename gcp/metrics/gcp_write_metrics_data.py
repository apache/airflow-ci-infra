#!/usr/bin/env python3
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
import time

import click
import requests
from google.cloud import monitoring_v3

DEFAULT_PROJECT = 'apache-airflow-ci-cd'
DEFAULT_ZONE = 'us-central1-a'
CUSTOM_METRICS_TYPE = 'custom.googleapis.com/github-actions/jobs-running'


@click.command()
@click.option('--project', default=DEFAULT_PROJECT)
@click.option('--instance')
@click.option('--value', type=int, default=1)
def main(project: str, instance: str, value):
    client = monitoring_v3.MetricServiceClient()
    project_name = f"projects/{project}"

    if not instance:
        instance = requests.get(
            "http://metadata/computeMetadata/v1/instance/id", headers={'Metadata-Flavor': 'Google'}
        ).text
    series = monitoring_v3.TimeSeries()
    series.metric.type = CUSTOM_METRICS_TYPE
    series.resource.type = "gce_instance"
    series.resource.labels["instance_id"] = instance
    series.resource.labels["zone"] = DEFAULT_ZONE
    now = time.time()
    seconds = int(now)
    nanos = int((now - seconds) * 10 ** 9)
    interval = monitoring_v3.TimeInterval({"end_time": {"seconds": seconds, "nanos": nanos}})
    point = monitoring_v3.Point({"interval": interval, "value": {"int64_value": value}})
    series.points = [point]
    client.create_time_series(name=project_name, time_series=[series])
    print(f"Reported {CUSTOM_METRICS_TYPE} with value {value}")


if __name__ == '__main__':
    main()
