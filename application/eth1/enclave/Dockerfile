#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

FROM amazonlinux:2

RUN yum install gcc python3 python3-devel net-tools -y

WORKDIR /app

COPY ./kms/kmstool_enclave_cli ./
COPY ./kms/libnsm.so /usr/lib64/

COPY requirements.txt ./
RUN pip3 install -r /app/requirements.txt

ARG REGION_ARG
ENV REGION=$REGION_ARG

COPY server.py ./
CMD [ "python3", "/app/server.py" ]
