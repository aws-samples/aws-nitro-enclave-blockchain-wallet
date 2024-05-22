#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

FROM alpine:3.19.1

RUN	set -ex; \
	apk add --no-cache iptables; \
	apk add --no-cache bind; \
    apk add --no-cache wireguard-tools; \
	apk add --no-cache iperf3; \
    apk add --no-cache socat

COPY ./run_socat.sh /

CMD /run_socat.sh