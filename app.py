#!/usr/bin/env python3

from aws_cdk import core

from nitro_wallet.nitro_wallet_stack import NitroWalletStack
from nitro_wallet.nitro_wallet_kms_stack import NitroWalletKMSStack

app = core.App()

# todo better naming
NitroWalletStack(app, "devNitroWallet", params={"deployment": "dev", "application_type": "decrypt"})
NitroWalletStack(app, "devNitroWalletEth", params={"deployment": "dev", "application_type": "eth1"})
NitroWalletKMSStack(app, "devNitroWalletKMS", params={"deployment": "dev"})

app.synth()
