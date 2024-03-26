#!/usr/bin/env python3

#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

import os
from aws_cdk import App, Environment, Aspects

from nitro_wallet.nitro_wallet_stack import NitroWalletStack
import cdk_nag

prefix = os.getenv("CDK_PREFIX", "dev")

app = App()

NitroWalletStack(
    app,
    f"{prefix}NitroWalletEth",
    params={"deployment": "dev", "application_type": "eth1"},
    env=Environment(
        # if not set us us-east-1 as default region to enable synth
        region=os.environ.get("CDK_DEPLOY_REGION", "us-east-1"),
        account=os.environ.get("CDK_DEPLOY_ACCOUNT")
    ),
)

NitroWalletStack(
    app,
    f"{prefix}NitroWireguard",
    params={"deployment": "dev", "application_type": "wireguard"},
    env=Environment(
        region=os.environ.get("CDK_DEPLOY_REGION", "us-east-1"),
        account=os.environ.get("CDK_DEPLOY_ACCOUNT")
    ),
)

Aspects.of(app).add(cdk_nag.AwsSolutionsChecks())
app.synth()
