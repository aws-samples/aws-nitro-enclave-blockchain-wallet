#!/usr/bin/env bash
#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

set -e
set -x

ifconfig lo 127.0.0.1
#ifconfig lo 127.0.0.2
route add -net 127.0.0.0 netmask 255.0.0.0 lo

echo "127.0.0.1 ${RDS_ENDPOINT_ADDRESS}" >>/etc/hosts
#echo "127.0.0.2 ssm.${REGION}.amazonaws.com" >>/etc/hosts

# start outbound proxy for dynamodb
IN_ADDRS=127.0.0.1:5432 OUT_ADDRS=3:8001 /app/proxy &
#IN_ADDRS=127.0.0.2:443 OUT_ADDRS=3:8002 /app/proxy &

python3 /app/server.py
