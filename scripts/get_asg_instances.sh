#!/usr/bin/env bash
#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

set +x
set -e

aws autoscaling describe-auto-scaling-instances --region ${CDK_DEPLOY_REGION}| jq -r '.AutoScalingInstances[] | select ( .AutoScalingGroupName == "'${1}'" ) | .InstanceId '
