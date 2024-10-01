#!/usr/bin/env bash

set +e
set -x

mkdir /var/cache/bind
named -c /etc/bind/named.conf -g &

# https://wiki.alpinelinux.org/wiki/Configure_a_Wireguard_interface_(wg)
# random config from https://www.wireguardconfig.com/
export LOG_LEVEL=debug
./wireguard-go-vsock wg0
ip address add dev wg0 203.0.113.1 peer 203.0.113.2

wg set wg0 \
      private-key /host.key \
      listen-port 10000 \
      peer ${WG_CLIENT_PUBLIC_KEY} \
      allowed-ips 0.0.0.0/0 \
      endpoint 0.0.0.16:10001


ip link set up dev wg0
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -o wg0 -j ACCEPT

while true
do
  ping -c 4 203.0.113.2
  ping -c 4 aws.com
  sleep 30
done