set -exu -o pipefail
echo "AWS_DEFAULT_REGION=$(cloud-init query region)" >> /etc/environment
set -a
. /etc/environment
set +a
echo "ASG_GROUP_NAME=$(aws ec2 describe-tags --filter Name=resource-id,Values=$(cloud-init query instance_id) Name=key,Values=aws:autoscaling:groupName \
    | jq -r '@sh "\(.Tags[0].Value)"')" >> /etc/environment
echo 'ACTIONS_SQS_URL=https://sqs.eu-central-1.amazonaws.com/827901512104/actions-runner-requests' >> /etc/environment
# Add environment to cron job
#cat /etc/environment >> /etc/cron.d/cloudwatch-metrics-github-runners
systemctl daemon-reload