#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
set -o xtrace

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
  libboost-regex1.74.0 \
  libboost-system1.74.0 \
  libprotobuf23 \
  libgoogle-perftools4 \
