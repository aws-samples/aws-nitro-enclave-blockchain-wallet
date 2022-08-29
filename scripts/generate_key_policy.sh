#!/usr/bin/env bash
#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0
set -e
set +x

output=${1}

# instance id
asg_name=$(jq -r '.devNitroWalletEth.ASGGroupName' ${output})
instance_id=$(./scripts/get_asg_instances.sh ${asg_name} | head -n 1)

# pcr_0
pcr_0=$(./scripts/get_pcr0.sh ${instance_id})

# ec2 role
ec2_role_arn=$(jq -r '.devNitroWalletEth.EC2InstanceRoleARN' ${output})
# lambda role
lambda_execution_arn=$(jq -r '.devNitroWalletEth.LambdaExecutionRoleARN' ${output})

# account
account_id=$( aws sts get-caller-identity | jq -r '.Account' )

cat ./scripts/kms_key_policy_template.json | jq '.Statement[0].Condition.StringEqualsIgnoreCase."kms:RecipientAttestation:ImageSha384"="'${pcr_0}'" | .Statement[0].Principal.AWS="'${ec2_role_arn}'" | .Statement[1].Principal.AWS="'${lambda_execution_arn}'" | .Statement[2].Principal.AWS="arn:aws:iam::'${account_id}':root"' | jq ''

