FROM amazonlinux

RUN yum install python3 net-tools -y

WORKDIR /app

COPY requirements.txt ./
RUN pip3 install -r /app/requirements.txt

COPY server.py ./
COPY traffic-forwarder.py ./
COPY run.sh ./

RUN chmod +x run.sh

CMD ["/app/run.sh"]
