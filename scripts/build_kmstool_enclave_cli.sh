#!/usr/bin/env bash
#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

set +x
set -e

NITRO_ENCLAVE_CLI_VERSION="v0.4.1"
KMS_FOLDER="./application/${CDK_APPLICATION_TYPE}/enclave/kms"
KMSTOOL_FOLDER="./aws-nitro-enclaves-sdk-c/bin/kmstool-enclave-cli"
TARGET_PLATFORM="linux/amd64"

if [[ ! -d ${KMS_FOLDER} ]]; then
  mkdir -p ${KMS_FOLDER}
fi

# delete repo if already there or if folder exists
rm -rf "${KMS_FOLDER}/aws-nitro-enclaves-sdk-c"

cd ${KMS_FOLDER}
git clone --depth 1 --branch ${NITRO_ENCLAVE_CLI_VERSION} https://github.com/aws/aws-nitro-enclaves-sdk-c.git

# for corporate networks disable GOPROXY
cd ./aws-nitro-enclaves-sdk-c/containers
awk 'NR==1{print; print "ARG GOPROXY=direct"} NR!=1' Dockerfile.al2 >Dockerfile.al2_new
cd ../../

cd ${KMSTOOL_FOLDER}

sed "s|-f ../../containers/Dockerfile.al2 ../..|-f ../../containers/Dockerfile.al2_new ../.. --platform=${TARGET_PLATFORM}|g" build.sh >build.sh_new
mv build.sh_new build.sh
chmod +x build.sh
./build.sh

cp ./kmstool_enclave_cli ../../../kmstool_enclave_cli
cp ./libnsm.so ../../../libnsm.so

cd -

rm -rf ./aws-nitro-enclaves-sdk-c

echo "kmstool_enclave_cli build successful"
