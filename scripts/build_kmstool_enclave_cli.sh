#!/usr/bin/env bash
#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

set +x
set -e

NITRO_ENCLAVE_CLI_VERSION="v0.3.2"
KMS_FOLDER="./application/eth1/enclave/kms"
KMSTOOL_FOLDER="./aws-nitro-enclaves-sdk-c/bin/kmstool-enclave-cli"

if [[ ! -d ${KMS_FOLDER} ]]; then
  mkdir -p ${KMS_FOLDER}
fi

# delete repo if already there or if folder exists
rm -rf "${KMS_FOLDER}/aws-nitro-enclaves-sdk-c"

cd ${KMS_FOLDER}
git clone --depth 1 --branch ${NITRO_ENCLAVE_CLI_VERSION} https://github.com/aws/aws-nitro-enclaves-sdk-c.git

# for corporate networks disable GOPROXY
cd ./aws-nitro-enclaves-sdk-c/containers
awk 'NR==1{print; print "ARG GOPROXY=direct"} NR!=1' Dockerfile.al2 > Dockerfile.al2_new
sed -i "" "s/--default-toolchain 1.60/--default-toolchain 1.63/g" Dockerfile.al2_new
mv Dockerfile.al2_new Dockerfile.al2
cd ../../

cd ${KMSTOOL_FOLDER}
./build.sh

cp ./kmstool_enclave_cli ../../../kmstool_enclave_cli
cp ./libnsm.so ../../../libnsm.so

cd -

rm -rf ./aws-nitro-enclaves-sdk-c

echo "kmstool_enclave_cli build successful"