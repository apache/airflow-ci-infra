#!/bin/bash
echo "Left-over containers:"
docker ps -a
docker ps -qa | xargs --verbose --no-run-if-empty docker rm -fv

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
fi