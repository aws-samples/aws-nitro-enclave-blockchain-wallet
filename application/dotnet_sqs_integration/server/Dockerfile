#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

FROM python:3.8

WORKDIR /usr/src/app

COPY ./app.py ./

COPY requirements.txt ./
RUN pip3 install -r /usr/src/app/requirements.txt

ARG REGION_ARG=us-east-1
ENV REGION=$REGION_ARG

CMD [ "python", "./app.py" ]