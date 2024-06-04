#!/bin/sh
#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

set -x
set -e

ifconfig lo 127.0.0.1
route add -net 127.0.0.0 netmask 255.0.0.0 lo

mount -o remount,exec /tmp
python3 /app/secure_server.py &
python3 /app/enclave.py