#!/usr/bin/env python3

import os
from aws_cdk import core
from nitro_wallet.nitro_wallet_stack import NitroWalletStack

app = core.App()

env = core.Environment(account=os.environ['DEV_ACCOUNT'],
                       region=os.environ['DEV_REGION'])

NitroWalletStack(app, "nitro-wallet")

app.synth()
