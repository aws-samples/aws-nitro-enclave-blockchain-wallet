#!/usr/bin/env bash
#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

set +x
set -e

WIREGUARD_VSOCK_REPO="https://github.com/seedcx/wireguard-go-vsock"
THIRD_PARTY_FOLDER="./application/wireguard/third_party"
WIREGUARD_VSOCK_FOLDER="wireguard-go-vsock"

# ensure that all 4 key variables are not empty / null
if [ -z "${WG_SERVER_PRIVATE_KEY}" ] && [ -z "${WG_SERVER_PUBLIC_KEY}" ] && [ -z "${WG_CLIENT_PRIVATE_KEY}" ] && [ -z "${WG_CLIENT_PUBLIC_KEY}" ]; then
  echo "Please set all the required environment variables"
  exit 1
fi

if [ ! -d ${THIRD_PARTY_FOLDER} ]; then
  mkdir -p ${THIRD_PARTY_FOLDER}
fi

# delete repo if already there or if folder exists
rm -rf "${THIRD_PARTY_FOLDER}/wireguard-go-vsock"

cd ${THIRD_PARTY_FOLDER}
git clone "${WIREGUARD_VSOCK_REPO}"

# stick with base64 representation of credentials for wg
echo "${WG_SERVER_PRIVATE_KEY}" > ../server/host.key
# inject client public key into server config / use '|' as delimiters to avoid sed complaining about '/' in base64 encoded public key
sed "s|      peer.*|      peer ${WG_CLIENT_PUBLIC_KEY} \\\|" ../server/run_server.sh > ../server/run_server.sh_new
mv ../server/run_server.sh_new ../server/run_server.sh
chmod +x ../server/run_server.sh

# convert to hex string for representation in golang
client_private_key=$(echo "${WG_CLIENT_PRIVATE_KEY}" | base64 -d | xxd -p -c 0)
server_public_key=$(echo "${WG_SERVER_PUBLIC_KEY}" | base64 -d | xxd -p -c 0)

cat <<EOF > "${WIREGUARD_VSOCK_FOLDER}"/client.go
package main

import (
	"fmt"
	"log"
	"os/exec"
	"time"

	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun"

	"github.com/seedcx/wireguard-go-vsock/vsockconn"
)

const retryInterval = 5 * time.Second

func main() {
	interfaceName := "wg0"
	localIP, remoteIP := "203.0.113.2", "203.0.113.1"
	tun, err := tun.CreateTUN(interfaceName, device.DefaultMTU)

	if err != nil {
		log.Panic(err)
	}

	realInterfaceName, err := tun.Name()

	if err == nil {
		interfaceName = realInterfaceName
	}

	cmd := exec.Command("ip", "address", "add", "dev", interfaceName, localIP, "peer", remoteIP)

	if err := cmd.Run(); err != nil {
		log.Panic(err)
	}

	logger := device.NewLogger(
		device.LogLevelVerbose,
		fmt.Sprintf("(%s) ", interfaceName),
	)
	bind := vsockconn.NewBind(logger)
	dev := device.NewDevice(tun, bind, logger)
    // private key supposed to be injected via secure bootstrapping mechanism
	err = dev.IpcSet(\`private_key=${client_private_key}
listen_port=10001
public_key=${server_public_key}
allowed_ip=0.0.0.0/0
endpoint=host(2):10000
\`)
	err = dev.Up()
	if err != nil {
		log.Panic(err)
	}

	for {
		time.Sleep(retryInterval)
	}
}

EOF

cd $WIREGUARD_VSOCK_FOLDER

# docker based building can be turned on if required - keeping it off for now due to faster and easier dependency management
#docker run --rm -e GOPROXY=direct -e CGO_ENABLED=0 -e GOOS=linux -e GOARCH=amd64 -v "${PWD}":/go/src/github.com/seedcx/wireguard-go-vsock -w /go/src/github.com/seedcx/wireguard-go-vsock golang:1.16.3 \
#  sh -x -c "go mod download github.com/mdlayher/socket && go build -v -o wireguard-go-vsock && go build -v client.go -o http-client-reduced"

# for corporate networks disable GOPROXY
#export GOPROXY=direct
export CGO_ENABLED=0
export GOOS=linux
export GOARCH=amd64
export GO111MODULE=on
# go mod tidy
go build -v -o wireguard-go-vsock main.go
go build -v -o wg-client client.go

chmod +x wg-client wireguard-go-vsock
mv wg-client ../../enclave
mv wireguard-go-vsock ../../server

cd ..
#rm -rf wireguard-go-vsock
