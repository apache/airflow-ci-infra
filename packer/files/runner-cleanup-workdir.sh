#!/bin/bash

if [[ -d ~runner/actions-runner/_work/airflow/airflow ]]; then
cd ~runner/actions-runner/_work/airflow/airflow

chown --changes -R runner: .
if [[ -e .git ]]; then
    sudo -u runner bash -c "
    git reset --hard && \
    git submodule deinit --all -f && \
    git submodule foreach git clean -fxd && \
    git clean -fxd \
    "
fi
docker ps -qa | xargs --no-run-if-empty docker rm -fv
fi

# We're idle now, ASG can kill us if it wants
aws autoscaling set-instance-protection  --no-protected-from-scale-in --instance-ids "$(cloud-init query instance_id)" --auto-scaling-group-name "$ASG_GROUP_NAME" >/dev/null

# Wait until we get an SQS message before continuing. This is mostly
# just for scailing reasons than anything else, and isn't really needed
# for actions runner to work
while true
do
msg="$(aws sqs receive-message --queue-url "$ACTIONS_SQS_URL" --max-number-of-messages 1)"
if [[ $? == 0 && -n "$msg" ]]; then
    # We got a message!
    aws --profile airflow sqs delete-message --queue-url "$ACTIONS_SQS_URL" --receipt-handle "$(jq '.Messages[0].ReceiptHandle' <<<"$msg" -r)"
    # Set our instance to "busy" so ASG doesn't try to kill us
    # TODO: This is a race -- some other runner may get the request from GitHub. We reset the protection
    # every minute via cron job anyway.
    aws autoscaling set-instance-protection --protected-from-scale-in --instance-ids "$(cloud-init query instance_id)" --auto-scaling-group-name "$ASG_GROUP_NAME" >/dev/null
    exit 0
fi
sleep 5

done