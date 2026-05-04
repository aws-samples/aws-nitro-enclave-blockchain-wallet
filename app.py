#!/usr/bin/env python3

#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

import os
from aws_cdk import App, Environment, Aspects

from nitro_wallet.nitro_wallet_stack import NitroWalletStack
from nitro_wallet.nitro_wireguard_stack import NitroWireguardStack
from nitro_wallet.nitro_socat_stack import NitroSocatStack
from nitro_wallet.nitro_rds_integration_stack import NitroRdsIntegrationStack
from nitro_wallet.nitro_https_web_server_stack import NitroHttpsWebServerStack
from nitro_wallet.nitro_dotnet_sqs_integration_stack import NitroDotnetSqsIntegrationStack
import cdk_nag

application_type = os.getenv("CDK_APPLICATION_TYPE", "eth1")

app = App()

VALID_DEPLOYMENTS = ("dev", "staging", "prod")
deployment = app.node.try_get_context("deployment") or os.getenv("CDK_DEPLOYMENT", "dev")
if deployment not in VALID_DEPLOYMENTS:
    raise ValueError(
        f"'deployment' must be one of {VALID_DEPLOYMENTS}, got: {deployment!r}. "
        "Pass --context deployment=dev (or staging/prod) to cdk deploy, "
        "or set CDK_DEPLOYMENT env var."
    )
prefix = app.node.try_get_context("prefix") or os.getenv("CDK_PREFIX", deployment)

if application_type == "eth1":
    NitroWalletStack(
        app,
        f"{prefix}NitroWalletEth",
        params={"deployment": deployment, "application_type": application_type},
        env=Environment(
            region=os.environ.get("CDK_DEPLOY_REGION"),
            account=os.environ.get("CDK_DEPLOY_ACCOUNT")
        ),
    )
elif application_type == "wireguard":
    NitroWireguardStack(
        app,
        f"{prefix}NitroWireguard",
        params={"deployment": deployment, "application_type": application_type},
        env=Environment(
            region=os.environ.get("CDK_DEPLOY_REGION"),
            account=os.environ.get("CDK_DEPLOY_ACCOUNT")
        ),
    )
elif application_type == "socat":
    NitroSocatStack(
        app,
        f"{prefix}NitroSocat",
        params={"deployment": deployment, "application_type": application_type},
        env=Environment(
            region=os.environ.get("CDK_DEPLOY_REGION"),
            account=os.environ.get("CDK_DEPLOY_ACCOUNT")
        ),
    )
elif application_type == "rds_integration":
    NitroRdsIntegrationStack(
        app,
        f"{prefix}NitroRdsIntegration",
        params={"deployment": deployment, "application_type": application_type},
        env=Environment(
            region=os.environ.get("CDK_DEPLOY_REGION"),
            account=os.environ.get("CDK_DEPLOY_ACCOUNT")
        ),
    )
elif application_type == "https_web_server":
    NitroHttpsWebServerStack(
        app,
        f"{prefix}NitroHttpsWebServer",
        params={"deployment": deployment, "application_type": application_type},
        env=Environment(
            region=os.environ.get("CDK_DEPLOY_REGION"),
            account=os.environ.get("CDK_DEPLOY_ACCOUNT")
        ),
    )
elif application_type == "dotnet_sqs_integration":
    NitroDotnetSqsIntegrationStack(
        app,
        f"{prefix}NitroDotnetSqsIntegration",
        params={"deployment": deployment, "application_type": application_type},
        env=Environment(
            region=os.environ.get("CDK_DEPLOY_REGION"),
            account=os.environ.get("CDK_DEPLOY_ACCOUNT")
        ),
    )

Aspects.of(app).add(cdk_nag.AwsSolutionsChecks())
app.synth()
