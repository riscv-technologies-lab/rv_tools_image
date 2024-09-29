#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
set -o xtrace

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  gpg-agent \
  lsb-release \
  software-properties-common \
  wget \

mkdir --parents /etc/apt/keyrings

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
  apt-transport-https \
  git \
  jq \
  tar gzip zip unzip bzip2 p7zip-full p7zip-rar xz-utils \
  gcc g++ \
  gawk \
  linux-tools-generic \
  make \
  pkg-config \
  cmake \
  device-tree-compiler \
  bash-completion \
  htop \
  less \
  openssh-client \
  openssh-server \
  sshpass \
  sudo \
  vim \
