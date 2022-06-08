#!/usr/bin/env python3

#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0


from aws_cdk import App

from nitro_wallet.nitro_wallet_stack import NitroWalletStack

app = App()

NitroWalletStack(app, "devNitroWalletEth", params={"deployment": "dev", "application_type": "eth1"})

app.synth()
