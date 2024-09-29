#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
set -o xtrace

PK_URL="https://github.com/riscv-software-src/riscv-pk.git"
PK_DIR="pk-src"
PK_TAG="v1.0.0"

git clone "${PK_URL}" "${PK_DIR}" --depth=1 -b "${PK_TAG}"
cd "${PK_DIR}"

set +o nounset
source "${SCDT_INSTALLATION_ROOT}"/env.sh
set -o nounset

# From riscv-pk readme:
mkdir build
cd build
../configure --prefix="${RISCV_TOOLS_PREFIX}" --host=riscv64-unknown-elf --with-arch=rv64gc
make "-j$(nproc)"
make install

cd ../..
rm -rf "${PK_DIR}"
