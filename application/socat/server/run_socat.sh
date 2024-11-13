#!/usr/bin/env bash
#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0
set +e
set -x

socat -b131072 TUN:192.168.86.1/24,iff-up VSOCK-LISTEN:12345,reuseaddr,fork &

# Vsock supports packet size of 64K, for stability purpose will use 55K instead
ip link set tun0 mtu 55000

# Enable IP Forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Allow established sessions to receive traffic, if not already allowed
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Masquerade traffic from Nitro Enclave, if not already masqueraded
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Forward traffic from tun0 to the default interface, if not already forwarded
iptables -A FORWARD -i tun0 -o eth0 -j ACCEPT

while true
do
  sleep 15
done