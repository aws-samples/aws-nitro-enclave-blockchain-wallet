#!/usr/bin/env python3

from aws_cdk import core

from nitro_wallet.nitro_wallet_stack import NitroWalletStack
from nitro_wallet.nitro_wallet_kms_stack import NitroWalletKMSStack

app = core.App()

# todo different sub stacks or different apps?
NitroWalletStack(app, "devNitroWallet", params={"deployment": "dev"})
NitroWalletKMSStack(app, "devNitroWalletKMS", params={"deployment": "dev"})

app.synth()
