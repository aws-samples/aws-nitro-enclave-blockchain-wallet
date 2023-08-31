#!/usr/bin/env python3

#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

import os
from aws_cdk import App, Environment, Aspects

from nitro_wallet.nitro_wallet_stack import NitroWalletStack
import cdk_nag

app = App()

NitroWalletStack(
    app,
    "devNitroWalletEth",
    params={"deployment": "dev", "application_type": "eth1"},
    env=Environment(
        region=os.environ.get("CDK_DEPLOY_REGION"),
        account=os.environ.get("CDK_DEPLOY_ACCOUNT")
    ),
)

Aspects.of(app).add(cdk_nag.AwsSolutionsChecks())
app.synth()
