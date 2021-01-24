set -exu -o pipefail
usermod -G docker -a runner
mkdir -p ~runner/actions-runner
cd ~runner/actions-runner
RUNNER_VERSION="2.276.0-airflow1"
curl -L "https://github.com/ashb/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" | tar -zx
aws s3 cp s3://airflow-ci-assets/get-runner-creds.py /opt/runner-creds-lock/bin/get-runner-creds
chmod 755 /opt/runner-creds-lock/bin/get-runner-creds
