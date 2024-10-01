#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

FROM amazonlinux:2
USER root

RUN yum install gcc python3 python3-devel net-tools mod_ssl httpd -y

WORKDIR /app
RUN mkdir /app/data
RUN mkdir /app/certs

ARG REGION_ARG
ENV REGION=$REGION_ARG

ENV LD_LIBRARY_PATH=/usr/lib64

RUN mkdir -p ./key_files
COPY requirements.txt ./

COPY enclave.py ./
COPY enclave_functions.py ./

COPY cert.pem /app/certs/
COPY key.pem /app/certs/
COPY secure_server.py /app/

RUN pip3 install -r /app/requirements.txt

COPY run.sh ./
RUN chmod +x /app/run.sh

ENTRYPOINT ["/app/run.sh"]
