#!/usr/bin/env sh

set +e
set -x

dmesg -n 7
uname -a
export LOG_LEVEL=debug
export GODEBUG=netdns=go+2

#./wireguard-go-vsock wg0
#ip address add dev wg0 203.0.113.2 peer 203.0.113.1

# todo host.key supposed to be protected by KMS
#wg set wg0 \
#      private-key /client.key \
#      listen-port 10001 \
#      peer <peer base64 encoded public key> \
#      allowed-ips 0.0.0.0/0 \
#      endpoint 0.0.0.2:10000

./wg-client &
sleep 60
ip link set up dev wg0

echo "nameserver 203.0.113.1" |  resolvconf -a tun.wg0 -m 0 -x
ip -4 route add 0.0.0.0/0 dev wg0

ifconfig

while true
do
  # ping p2p endpoint on docker container on parent instance
  ping -c 4 203.0.113.1
  # test dns resolution from inside enclave
  ping -c 4 aws.com

  sleep 30
done
#iperf3 -s -f K
