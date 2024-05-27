# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

FROM amazonlinux:2

RUN yum install gcc python3 python3-devel net-tools tar.x86_64 -y

COPY dotnet-install.sh .

RUN chmod +x ./dotnet-install.sh
RUN ./dotnet-install.sh --channel 6.0

ARG REGION_ARG
ENV REGION=$REGION_ARG

COPY ./netenclave/bin/ .
COPY run.sh .
COPY ./proxy/proxy .

CMD [ "sh", "run.sh" ]