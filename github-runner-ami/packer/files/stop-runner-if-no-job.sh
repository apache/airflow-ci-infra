#!/bin/bash
set -u

MAINPID="${MAINPID:-${1:-}}"

if [[ -z "$MAINPID" ]]; then
    echo "No MAINPID, assuming it already crashed!"
    exit 0
fi

if pgrep --ns $MAINPID -a Runner.Worker > /dev/null; then
  echo "Waiting for current job to finish"
  while pgrep --ns $MAINPID -a Runner.Worker; do
    # Job running -- just wait for it to exit
    sleep 10
  done
fi

# Request shutdown if it's still alive -- because we are in "stop" state it should not restart
if pkill --ns $MAINPID Runner.Listener; then
  # Wait for it to shut down
  echo "Waiting for main Runner.Listener process to stop"
  while pgrep --ns $MAINPID -a Runner.Listener; do
    sleep 5
  done
fi