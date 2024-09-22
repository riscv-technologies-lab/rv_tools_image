#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
set -o xtrace

pip install gdown

FILEID="1bon577_SBAIwLkxDstTtV7f18ZkRNJ5S"
# TODO: make automatic filename deducing
SC_DT_VERSION="sc-dt-2024.08"
FILENAME="${SC_DT_VERSION}.tar.gz"
gdown ${FILEID}

echo "$(ls)"
tar -xf ${FILENAME} -C /opt
rm -rf ${FILENAME}
