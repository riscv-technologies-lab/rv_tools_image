#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
set -o xtrace

COREMARK_URL="https://github.com/eembc/coremark.git"
COREMARK_DIR="/opt/coremark"

git clone "${COREMARK_URL}" "${COREMARK_DIR}"
cd "${COREMARK_DIR}"

set +o nounset
source "${SCDT_INSTALLATION_ROOT}"/env.sh
set -o nounset
make CC=riscv64-unknown-linux-gnu-gcc XCFLAGS=-static ITERATIONS=1 link
