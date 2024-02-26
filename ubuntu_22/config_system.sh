#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
set -o xtrace

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
  bash-completion \
  ccache \
  device-tree-compiler \
  htop \
  less \
  lftp \
  libncurses5 \
  ninja-build \
  openssh-client \
  openssh-server \
  sshpass \
  vim \
