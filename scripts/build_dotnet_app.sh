#!/usr/bin/env bash
#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

set +x
set -e

NITRO_ENCLAVE_CLI_VERSION="v0.4.1"
DOTNET_FOLDER="./application/${CDK_APPLICATION_TYPE}/enclave/netenclave"
# KMSTOOL_FOLDER="./aws-nitro-enclaves-sdk-c/bin/kmstool-enclave-cli"
TARGET_PLATFORM="linux/amd64"

# if [[ ! -d ${KMS_FOLDER} ]]; then
#   mkdir -p ${KMS_FOLDER}
# fi

# ./application/eth1/enclave/dotnet-install.sh --channel 6.0
sudo yum install dotnet -y

# # delete repo if already there or if folder exists
# rm -rf "${KMS_FOLDER}/aws-nitro-enclaves-sdk-c"

cd ${DOTNET_FOLDER}

dotnet build

# # for corporate networks disable GOPROXY
# cd ./aws-nitro-enclaves-sdk-c/containers
# awk 'NR==1{print; print "ARG GOPROXY=direct"} NR!=1' Dockerfile.al2 >Dockerfile.al2_new
cd ../

# cd ${KMSTOOL_FOLDER}

# sed "s|-f ../../containers/Dockerfile.al2 ../..|-f ../../containers/Dockerfile.al2_new ../.. --platform=${TARGET_PLATFORM}|g" build.sh >build.sh_new
# mv build.sh_new build.sh
# chmod +x build.sh
# ./build.sh

# cp ./kmstool_enclave_cli ../../../kmstool_enclave_cli
# cp ./libnsm.so ../../../libnsm.so

# cd -

# rm -rf ./aws-nitro-enclaves-sdk-c

echo "dotnet app build successful"
