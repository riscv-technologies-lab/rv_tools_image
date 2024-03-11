#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
set -o xtrace

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
  build-essential \
  git \
  m4 \
  scons \
  zlib1g \
  zlib1g-dev \
  libprotobuf-dev \
  protobuf-compiler \
  libprotoc-dev \
  libgoogle-perftools-dev \
  python3-dev \
  python3

GEM5_URL="https://github.com/gem5/gem5"
GEM5_DIR="/opt/gem5"

git clone "${GEM5_URL}" "${GEM5_DIR}"
cd "${GEM5_DIR}"

python3 "$(which scons)" build/RISCV/gem5.opt "-j$(nproc)"

ln -s "${GEM5_DIR}/build/RISCV/gem5.opt" /bin/gem5
