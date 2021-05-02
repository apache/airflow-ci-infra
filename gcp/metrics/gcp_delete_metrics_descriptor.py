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

import click
from google.cloud import monitoring_v3

DEFAULT_PROJECT = 'apache-airflow-ci-cd'
DEFAULT_ZONE = 'us-central1-a'
CUSTOM_METRICS_TYPE = 'custom.googleapis.com/github-actions/jobs-running'


@click.command()
@click.option('--project', default=DEFAULT_PROJECT)
@click.option('--zone', default=DEFAULT_ZONE)
def main(project: str, zone: str):
    client = monitoring_v3.MetricServiceClient()
    descriptor_name = f"projects/{project}/metricDescriptors/{CUSTOM_METRICS_TYPE}"
    client.delete_metric_descriptor(name=descriptor_name)
    print(f"Deleted metric descriptor {descriptor_name}.")


if __name__ == '__main__':
    main()
