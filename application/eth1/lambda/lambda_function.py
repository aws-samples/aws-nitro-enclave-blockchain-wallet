#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

import base64
import json
import logging
import os
import ssl
from http import client

import boto3

ssl_context = ssl.SSLContext()
ssl_context.verify_mode = ssl.CERT_NONE


LOG_LEVEL = os.getenv("LOG_LEVEL", "WARNING")
LOG_FORMAT = "%(levelname)s:%(lineno)s:%(message)s"
handler = logging.StreamHandler()

_logger = logging.getLogger("tx_manager_controller")
_logger.setLevel(LOG_LEVEL)
_logger.addHandler(handler)
_logger.propagate = False

client_kms = boto3.client("kms")
client_secrets_manager = boto3.client("secretsmanager")


def lambda_handler(event, context):
    """
    example requests
    {
      "operation": "set_key",
      "eth_key": "123"
    }

    {
      "operation": "get_key"
    }

    {
      "operation": "sign_transaction",
      "transaction_payload": {
        "value": 0.01,
        "to": "0xa5D3241A1591061F2a4bB69CA0215F66520E67cf",
        "nonce": 0,
        "type": 2,
        "chainId": 4,
        "gas": 100000,
        "maxFeePerGas": 100000000000,
        "maxPriorityFeePerGas": 3000000000
        }
    }

    """
    nitro_instance_private_dns = os.getenv("NITRO_INSTANCE_PRIVATE_DNS")
    secret_id = os.getenv("SECRET_ARN")
    key_id = os.getenv("KEY_ARN")

    if not (nitro_instance_private_dns and secret_id and key_id):
        _logger.fatal(
            "NITRO_INSTANCE_PRIVATE_DNS, SECRET_ARN and KEY_ARN environment variables need to be set"
        )

    operation = event.get("operation")
    if not operation:
        _logger.fatal("request needs to define operation")

    if operation == "set_key":
        key_plaintext = event.get("eth_key")

        try:
            response = client_kms.encrypt(
                KeyId=key_id, Plaintext=key_plaintext.encode()
            )
        except Exception as e:
            raise Exception(
                "exception happened sending decryption request to KMS: {}".format(e)
            )

        _logger.debug("response: {}".format(response))
        response_b64 = base64.standard_b64encode(response["CiphertextBlob"]).decode()

        try:
            response = client_secrets_manager.update_secret(
                SecretId=secret_id,
                # rely on the AWS managed key for std. storage
                SecretString=response_b64,
            )
        except Exception as e:
            raise Exception("exception happened updating secret: {}".format(e))

        return response

    elif operation == "get_key":
        try:
            response = client_secrets_manager.get_secret_value(SecretId=secret_id)
        except Exception as e:
            raise Exception(
                "exception happened reading secret from secrets manager: {}".format(e)
            )

        return response["SecretString"]

    # sign_transaction

    elif operation == "sign_transaction":
        transaction_payload = event.get("transaction_payload")

        if not transaction_payload:
            raise Exception(
                "sign_transaction requires transaction_payload and secret_id optionally"
            )

        https_nitro_client = client.HTTPSConnection(
            "{}:{}".format(nitro_instance_private_dns, 443), context=ssl_context
        )

        try:
            https_nitro_client.request(
                "POST",
                "/",
                body=json.dumps(
                    {"transaction_payload": transaction_payload, "secret_id": secret_id}
                ),
            )
            response = https_nitro_client.getresponse()
        except Exception as e:
            raise Exception(
                "exception happened sending decryption request to Nitro Enclave: {}".format(
                    e
                )
            )

        _logger.debug("response: {} {}".format(response.status, response.reason))

        response_raw = response.read()

        _logger.debug("response data: {}".format(response_raw))
        response_parsed = json.loads(response_raw)

        return response_parsed

    else:
        _logger.fatal("operation: {} not supported right now".format(operation))
