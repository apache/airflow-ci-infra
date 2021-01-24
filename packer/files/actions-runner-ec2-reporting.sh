#!/bin/bash

if pgrep -c Runner.Worker >/dev/null; then
# Only report metric when we're doing something -- no point paying to submit zeros
    aws cloudwatch put-metric-data --metric-name jobs-running --value "$(pgrep -c Runner.Worker)" --namespace github.actions
    protection=--protected-from-scale-in
else
    protection=--no-protected-from-scale-in
fi
aws autoscaling set-instance-protection "$protection" --instance-ids "$(cloud-init query instance_id)" --auto-scaling-group-name "$ASG_GROUP_NAME" >/dev/null