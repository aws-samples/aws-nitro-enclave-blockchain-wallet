#!/usr/bin/env bash
#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0
set +x
set -e

target_architecture=${CDK_TARGET_ARCHITECTURE:-linux/amd64}
PROXY_TARGET_DIRECTORY="./application/${CDK_APPLICATION_TYPE}/enclave/proxy"

if [[ ! -d ${PROXY_TARGET_DIRECTORY} ]]; then
  mkdir -p ${PROXY_TARGET_DIRECTORY}
fi

cd "${PROXY_TARGET_DIRECTORY}"

if [[ -d "./viproxy" ]]; then
  rm -rf "./viproxy"
fi

git clone https://github.com/brave/viproxy.git
cd ./viproxy

cat <<EOF | git apply --ignore-space-change --ignore-whitespace
diff --git a/example/main.go b/example/main.go
index d202bd8..25bf477 100644
--- a/example/main.go
+++ b/example/main.go
@@ -26,7 +26,7 @@ func parseAddr(rawAddr string) net.Addr {
        if len(fields) != 2 {
                log.Fatal("Looks like we're given neither AF_INET nor AF_VSOCK addr.")
        }
-       cid, err := strconv.ParseInt(fields[0], 10, 32)
+       cid, err := strconv.ParseInt(fields[0], 10, 64)
        if err != nil {
                log.Fatal("Couldn't turn CID into integer.")
        }
EOF

architecture=$(echo "${target_architecture}" | cut -d "/" -f 2)
env GOOS=linux GOARCH="${architecture}" CGO_ENABLED=0 go build ./example/main.go
cp main ../proxy
cd ..
rm -rf ./viproxy
