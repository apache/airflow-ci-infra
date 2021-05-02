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
from google.api import label_pb2 as ga_label, metric_pb2 as ga_metric
from google.cloud import monitoring_v3

DEFAULT_PROJECT = 'apache-airflow-ci-cd'
DEFAULT_ZONE = 'us-central1-a'
CUSTOM_METRICS_TYPE = 'custom.googleapis.com/github-actions/jobs-running'


@click.command()
@click.option('--project', default=DEFAULT_PROJECT)
def main(project: str):
    client = monitoring_v3.MetricServiceClient()
    project_name = f"projects/{project}"
    descriptor = ga_metric.MetricDescriptor(
        display_name="GitHub Actions jobs",
        type=CUSTOM_METRICS_TYPE,
        metric_kind=ga_metric.MetricDescriptor.MetricKind.GAUGE,
        value_type=ga_metric.MetricDescriptor.ValueType.INT64,
        description="Number of Jobs running for GitHub Actions.",
    )

    label_instance_id = ga_label.LabelDescriptor(
        key="instance_id", value_type=ga_label.LabelDescriptor.ValueType.STRING, description="The instance_id"
    )
    label_zone = ga_label.LabelDescriptor(
        key="zone", value_type=ga_label.LabelDescriptor.ValueType.STRING, description="The zone"
    )
    descriptor.labels.append(label_instance_id)
    descriptor.labels.append(label_zone)

    descriptor = client.create_metric_descriptor(name=project_name, metric_descriptor=descriptor)
    print(f"Created {descriptor.name}.")


if __name__ == '__main__':
    main()
