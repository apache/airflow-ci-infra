ARG ACTIONS_RUNNER_VERSION=v2.309.0-ubuntu-22.04-ead26ab

FROM summerwind/actions-runner:${ACTIONS_RUNNER_VERSION}

USER root

ARG AIRFLOW_RUNNER_VERSION=2.309.0-airflow11

RUN rm -rf $RUNNER_ASSETS_DIR/* \
    && export ARCH=$(arch) \
    && if [ "$ARCH" = "amd64" ] || [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "i386" ]; then export ARCH=x64 ; fi \
    && if [ "$ARCH" = "aarch64" ]; then export ARCH=arm64 ; fi \
    && cd "$RUNNER_ASSETS_DIR" \
    && curl -fLo runner.tar.gz "https://github.com/ashb/runner/releases/download/v${AIRFLOW_RUNNER_VERSION}/actions-runner-linux-${ARCH}-${AIRFLOW_RUNNER_VERSION}.tar.gz" \
    && tar xzf ./runner.tar.gz \
    && rm runner.tar.gz \
    && ./bin/installdependencies.sh \
    && mv ./externals ./externalstmp

# TODO: Remove this once https://github.com/actions/setup-python/issues/705 is solved
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl nodejs wget unzip vim git jq build-essential libssl-dev libffi-dev python3 python3-venv python3-dev python3-pip python-is-python3 \
    && chown -R runner:runner /usr/local/lib/ --recursive \
    && chown -R runner:runner /usr/local/bin/ --recursive

USER runner