#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

FROM python:3.11-slim

WORKDIR /usr/src/app

COPY requirements.txt ./
RUN pip3 install --no-cache-dir -r /usr/src/app/requirements.txt

COPY ./app.py ./

ARG REGION_ARG=us-east-1
ENV REGION=$REGION_ARG

CMD [ "python", "./app.py" ]
