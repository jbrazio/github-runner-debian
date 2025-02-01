FROM debian:12-slim

LABEL org.opencontainers.image.description="Github Actions custom runner"
LABEL org.opencontainers.image.source=https://github.com/jbrazio/github-runner-debian.git
LABEL org.opencontainers.image.licenses=GPL-3.0-or-later

# update the base packages and add a non-sudo user
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y && apt-get upgrade -y

# add a standard account
RUN useradd -ms /bin/bash debian

# # install sudo and allow the debian user to run sudo commands without a password
# RUN apt-get install -y --no-install-recommends sudo \
#   && echo "debian ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/debian \

# add additional packages
RUN apt-get install -y --no-install-recommends \
  build-essential ca-certificates curl curl git gh gnupg jq libffi-dev libssl-dev python3 python3-dev python3-pip python3-venv

# https://github.com/actions/runner/releases
ARG RUNNER_VERSION="2.321.0"
ARG RUNNER_CHECKSUM="ba46ba7ce3a4d7236b16fbe44419fb453bc08f866b24f04d549ec89f1722a29e"

# download and unzip the github actions runner
RUN curl -o /tmp/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
  && echo "${RUNNER_CHECKSUM}  /tmp/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" | shasum -a 256 -c \
  && tar xzf /tmp/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -C /home/debian \
  && /home/debian/bin/installdependencies.sh

# # download and install nodejs
# ENV NODE_VERSION=22.x
# RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION} | bash - \
#   && apt-get install -y --no-install-recommends nodejs \
#   && node --version && npm --version

# remove build dependencies and unnecessary files
RUN apt-get clean \
  && rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*

# prepare the entrypoint script
RUN cat >> /docker-entrypoint.sh <<EOF
#!/bin/bash
set -e

ORGANIZATION=\${ORGANIZATION}
ACCESS_TOKEN=\${ACCESS_TOKEN}

RUNNER_TOKEN=$(curl -sX POST -H "Authorization: token \${ACCESS_TOKEN}" \
	https://api.github.com/orgs/\${ORGANIZATION}/actions/runners/registration-token | jq .token --raw-output)

if [ -z "\$RUNNER_TOKEN" ]; then
    echo "Failed to retrieve runner token. Exiting."
    exit 1
fi

cd /home/debian
./config.sh --unattended --url https://github.com/\${ORGANIZATION} --token \${RUNNER_TOKEN}

cleanup() {
    echo "Removing runner..."
    ./config.sh remove --token \${RUNNER_TOKEN}
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

./run.sh & wait $!
EOF

RUN chmod +x /docker-entrypoint.sh \
  && chown -R debian:debian /home/debian

# set the entrypoint to the start.sh script
USER debian
ENTRYPOINT ["/docker-entrypoint.sh"]
