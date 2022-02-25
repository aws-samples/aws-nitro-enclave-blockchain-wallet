#!/usr/bin/env bash

set +x
set -e



aws autoscaling describe-auto-scaling-instances | jq -r '.AutoScalingInstances[] | select ( .AutoScalingGroupName == "'${1}'" ) | .InstanceId '