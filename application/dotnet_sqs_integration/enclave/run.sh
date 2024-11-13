#!/usr/bin/env bash
#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

set -e
set -x

ifconfig lo 127.0.0.1
#ifconfig lo 127.0.0.2
route add -net 127.0.0.0 netmask 255.0.0.0 lo

echo "127.0.0.1 sqs.${REGION}.amazonaws.com" >>/etc/hosts

# start outbound proxy for dynamodb
IN_ADDRS=127.0.0.1:443 OUT_ADDRS=3:8001 ./proxy &
IN_ADDRS=127.0.0.1:80 OUT_ADDRS=3:8002 ./proxy &

export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
./root/.dotnet/dotnet /Debug/net6.0/netenclave.dll ${REGION}
