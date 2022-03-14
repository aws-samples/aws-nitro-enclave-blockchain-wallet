FROM amazonlinux

#RUN yum groupinstall "Development Tools" -y
# todo external build and copy over for smaller docker image size
RUN yum install gcc python3 python3-devel net-tools -y

WORKDIR /app

COPY ./kms/kmstool_enclave_cli ./
COPY ./kms/libnsm.so /usr/lib64/

COPY requirements.txt ./
RUN pip3 install -r /app/requirements.txt

COPY server.py ./
#COPY traffic-forwarder.py ./
#COPY run.sh ./

#RUN chmod +x run.sh

#CMD ["/app/run.sh"]
CMD [ "python3", "/app/server.py" ]