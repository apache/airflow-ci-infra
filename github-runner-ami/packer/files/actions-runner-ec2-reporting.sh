#!/bin/bash
if pgrep -c Runner.Worker >/dev/null; then
    # Only report metric when we're doing something -- no point paying to submit zeros
    aws cloudwatch put-metric-data --metric-name jobs-running --value "$(pgrep -c Runner.Worker)" --namespace github.actions
fi