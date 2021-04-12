
URL=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.assets[].browser_download_url | select(endswith("docker-compose-Linux-x86_64"))')
curl -L $URL -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
set -exu -o pipefail
echo "AWS_DEFAULT_REGION=$(cloud-init query region)" >> /etc/environment
# Set an env var (that is visible in runners) that will let us know we are on a self-hosted runner
echo 'AIRFLOW_SELF_HOSTED_RUNNER="[\"self-hosted\"]"' >> /etc/environment
set -a
. /etc/environment
set +a
systemctl daemon-reload
set -exu -o pipefail
usermod -G docker -a runner
mkdir -p ~runner/actions-runner
find ~runner -exec  chown runner: {} +
cd ~runner/actions-runner
RUNNER_VERSION="$0"
curl -L "https://github.com/ashb/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" | tar -zx
set -a
. /etc/environment
set +a
aws s3 cp s3://airflow-ci-assets/runner-supervisor.py /opt/runner-supervisor/bin/runner-supervisor
chmod 755 /opt/runner-supervisor/bin/runner-supervisor
# Log in to a paid docker user to get unlimited docker pulls
aws ssm get-parameter --with-decryption --name /runners/apache/airflow/dockerPassword | \
jq .Parameter.Value -r | \
sudo -u runner docker login --username airflowcirunners --password-stdin
2.277.1-airflow1
systemctl enable --now iptables.service
# Restart docker after applying the user firewall -- else some rules/chains might be list!
systemctl restart docker.service
systemctl enable now vector.service
systemctl enable --now actions.runner.service
