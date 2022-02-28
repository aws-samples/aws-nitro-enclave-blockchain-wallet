#!/usr/bin/env bash

set +x
set -e

aws autoscaling start-instance-refresh --auto-scaling-group-name ${1}