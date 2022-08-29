#!/usr/bin/env python3

#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

import os
from aws_cdk import App, Environment

from nitro_wallet.nitro_wallet_stack import NitroWalletStack

app = App()

NitroWalletStack(app, "devNitroWalletEth", params={"deployment": "dev", "application_type": "eth1"},
                 env=Environment(region=os.environ.get("CDK_DEPLOY_REGION", os.environ["CDK_DEFAULT_REGION"])))

app.synth()
