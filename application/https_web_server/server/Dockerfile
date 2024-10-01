#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

FROM python:3.9

WORKDIR /usr/src/app

COPY ./app.py ./

COPY requirements.txt ./
RUN pip3 install -r /usr/src/app/requirements.txt

CMD [ "python", "./app.py" ]