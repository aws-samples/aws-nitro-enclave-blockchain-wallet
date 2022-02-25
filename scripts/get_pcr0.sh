#!/usr/bin/env bash

set +x
set -e

command_id=$(aws ssm send-command --document-name "AWS-RunShellScript" --instance-ids ${1} --parameters 'commands=["sudo nitro-cli describe-enclaves | jq -r '.[].Measurements.PCR0'"]' | jq -r '.Command.CommandId')
pcr_0=$(aws ssm list-command-invocations --instance-id ${1} --command-id ${command_id} --details | jq -r '.CommandInvocations[0].CommandPlugins[0].Output')
echo ${pcr_0}
