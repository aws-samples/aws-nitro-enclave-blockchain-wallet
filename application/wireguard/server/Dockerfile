FROM alpine:3.19.1

RUN	set -ex; \
	apk add --no-cache iptables; \
	apk add --no-cache bind; \
    apk add --no-cache wireguard-tools; \
	apk add --no-cache iperf3;

COPY ./host.key /
COPY ./named.conf /etc/bind/
COPY ./wireguard-go-vsock /
COPY ./run_server.sh /

CMD /run_server.sh
