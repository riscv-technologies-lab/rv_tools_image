#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
set -o xtrace

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
  libboost-regex-dev \
  libboost-system-dev \

SPIKE_URL="https://github.com/riscv-software-src/riscv-isa-sim.git"
SPIKE_DIR="spike-src"
SPIKE_COMMIT="c95a2cbd68923a2925eed0ff1af00870661bb2cb"

git clone "${SPIKE_URL}" "${SPIKE_DIR}"
cd "${SPIKE_DIR}"
git checkout "${SPIKE_COMMIT}"

# From riscv-isa-sim readme:
mkdir build
cd build
../configure --prefix="${RISCV_TOOLS_PREFIX}"
make "-j$(nproc)"
make install

cd ../..
rm -rf "${SPIKE_DIR}"
