#!/usr/bin/env sh
#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

set +e
set -x

socat -b131072 TUN:192.168.86.2/24,iff-up VSOCK-CONNECT:3:12345 &

# Setting MTU to max supported size, can be adjusted from parent instance for point-to-point connection testing
ip link set tun0 mtu 65535

ip route add default via 192.168.86.1
mkdir /run/resolvconf

echo "options single-request" >/run/resolvconf/resolv.conf
echo "nameserver 1.1.1.1" >>/run/resolvconf/resolv.conf

ping -c 4 aws.com
# iperf3 -s -f K
