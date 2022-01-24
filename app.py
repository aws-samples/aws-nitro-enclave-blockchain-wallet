#!/usr/bin/env python3

from aws_cdk import core

from nitro_wallet.nitro_wallet_stack import NitroWalletStack

app = core.App()

NitroWalletStack(app, "devNitroWallet", params={"deployment": "dev"})

app.synth()
