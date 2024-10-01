FROM alpine:3.19.1

RUN	set -ex; \
	apk add --no-cache iptables; \
    apk add --no-cache wireguard-tools; \
	apk add --no-cache iperf3;

COPY ./run_client.sh /
COPY ./wg-client /

CMD /run_client.sh
