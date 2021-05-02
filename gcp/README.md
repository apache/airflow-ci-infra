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

# Notes from setting up GCP version of Airflow CI runner

Those are notes taken while setting-up GCP version of the Runner.

1. Created a new service account without any permissions

airlfow-ci-runner@apache-airflow-ci-cd.iam.gserviceaccount.com

2. Created custom roles with those permissions:

* Monitoring Metric Writer
    * monitoring.timeSeries.create

2. Created `runners-apache-airflow-dockerPassword` secret with the same value as in AWS.

3. Assigned roles to the "airflow-ci-runner" service account:

* Monitoring Metric Writer
* Secret Manager Secret Accessor


4. Created `airflow-ci-assets` GCS bucket with "public read" permissions

5. Copied those files there (they need to be copied every time they are changed)
   * gcp_write_metrics_data.py
   * get-runner-creds.py
   * requirements.txt
   * runner-supervisor.py

6. Configured federated login to AWS so that the GCP Service Account can login to AWS

Followed this post: https://cevo.com.au/post/2019-07-29-using-gcp-service-accounts-to-access-aws/

But I had to implement some changes (the latest Google Account) - changes captured in
[this PR](https://github.com/potiuk/gcp-sa-to-aws-iam-role/tree/update-latest-google-ocid-host)
