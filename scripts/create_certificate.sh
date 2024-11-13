#!/usr/bin/env bash
#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

set +x
set -e

CERT_FOLDER="./application/${CDK_APPLICATION_TYPE}/enclave"

cd ${CERT_FOLDER}

openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -sha256 -days 3650 -nodes -subj "/C=US/O=AWS/OU=Blockchain Compute/CN=example.com"

echo "Self-signed certificate created successfully"
