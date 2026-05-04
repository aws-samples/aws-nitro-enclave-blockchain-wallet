#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

import base64
import json
import logging
import os
import ssl
from http import client

import boto3
from eth_keys import keys as eth_keys

ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
ca_cert_path = os.getenv("NITRO_CA_CERT_PATH")
skip_tls_verify = os.getenv("NITRO_SKIP_TLS_VERIFY", "").lower() in ("true", "1")
if ca_cert_path:
    ssl_context.load_verify_locations(ca_cert_path)
    ssl_context.verify_mode = ssl.CERT_REQUIRED
elif skip_tls_verify:
    # Explicitly opted-in to skip verification (dev/test only)
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE
else:
    # Default: use system CA store with full verification
    ssl_context.load_default_certs()
    ssl_context.verify_mode = ssl.CERT_REQUIRED


LOG_LEVEL = os.getenv("LOG_LEVEL", "WARNING")
LOG_FORMAT = "%(levelname)s:%(lineno)s:%(message)s"
handler = logging.StreamHandler()

_logger = logging.getLogger("tx_manager_controller")
_logger.setLevel(LOG_LEVEL)
_logger.addHandler(handler)
_logger.propagate = False

client_kms = boto3.client("kms")
client_secrets_manager = boto3.client("secretsmanager")


def _validate_hash(hash_value):
    """Validate that hash_value is exactly 32 bytes of hex."""
    if not hash_value:
        raise ValueError("sign_hash requires a 'hash' field")
    hash_clean = hash_value.replace("0x", "")
    if len(hash_clean) != 64:
        raise ValueError(
            "Hash must be exactly 32 bytes (64 hex chars), got {} chars".format(len(hash_clean))
        )
    try:
        bytes.fromhex(hash_clean)
    except ValueError:
        raise ValueError("Hash contains invalid hex characters")
    return hash_clean


def _verify_recovered_address(hash_hex, signature, expected_address):
    """Verify that the signature recovers to the expected address.

    Provides defense-in-depth against forged or malformed signatures
    by performing ecrecover on the Lambda side.
    """
    hash_clean = hash_hex.replace("0x", "")
    hash_bytes = bytes.fromhex(hash_clean)

    r = int(signature["r"], 16)
    s = int(signature["s"], 16)
    # eth_keys uses v as 0 or 1 (not 27/28)
    v_normalized = signature["v"] - 27

    sig = eth_keys.Signature(vrs=(v_normalized, r, s))
    recovered_key = sig.recover_public_key_from_msg_hash(hash_bytes)
    recovered_address = recovered_key.to_checksum_address()

    if recovered_address.lower() != expected_address.lower():
        raise Exception(
            "Signature verification failed: recovered {} but expected {}".format(
                recovered_address, expected_address
            )
        )


def lambda_handler(event, context):
    """
    example requests

    Set an externally-generated key:
    {
      "operation": "set_key",
      "eth_key": "0x..."
    }

    Read encrypted key ciphertext:
    {
      "operation": "get_key"
    }

    Generate a new key inside the enclave:
    {
      "operation": "generate_key",
      "secret_name": "nitro-wallet/my-key"
    }

    Sign a transaction:
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

    Sign a raw hash (e.g. EIP-712 typed data):
    {
      "operation": "sign_hash",
      "hash": "0x<64 hex chars>",
      "expected_address": "0x..."  (optional, enables ecrecover verification)
    }

    """
    nitro_instance_private_dns = os.getenv("NITRO_INSTANCE_PRIVATE_DNS")
    secret_id = os.getenv("SECRET_ARN")
    key_id = os.getenv("KEY_ARN")

    if not (nitro_instance_private_dns and secret_id and key_id):
        raise ValueError(
            "NITRO_INSTANCE_PRIVATE_DNS, SECRET_ARN and KEY_ARN environment variables need to be set"
        )

    operation = event.get("operation")
    if not operation:
        raise ValueError("request needs to define operation")

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

    elif operation == "generate_key":
        secret_name = event.get("secret_name")
        if not secret_name:
            raise Exception("generate_key requires secret_name")

        https_nitro_client = client.HTTPSConnection(
            "{}:{}".format(nitro_instance_private_dns, 443), context=ssl_context
        )

        try:
            https_nitro_client.request(
                "POST",
                "/generate_key",
                body=json.dumps({"key_id": key_id}),
            )
            response = https_nitro_client.getresponse()
        except Exception as e:
            raise Exception(
                "exception happened calling Nitro Enclave for key generation: {}".format(e)
            )

        response_raw = response.read()
        response_parsed = json.loads(response_raw)

        if "error" in response_parsed:
            raise Exception("Enclave error: {}".format(response_parsed["error"]))

        encrypted_key = response_parsed["encrypted_key"]
        address = response_parsed["address"]

        try:
            client_secrets_manager.create_secret(
                Name=secret_name,
                SecretString=encrypted_key,
                Description=f"Encrypted Ethereum key for {address}",
            )
        except client_secrets_manager.exceptions.ResourceExistsException:
            client_secrets_manager.update_secret(
                SecretId=secret_name,
                SecretString=encrypted_key,
            )

        return {
            "address": address,
            "secret_name": secret_name,
        }

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

    elif operation == "sign_hash":
        hash_value = event.get("hash")
        _validate_hash(hash_value)

        https_nitro_client = client.HTTPSConnection(
            "{}:{}".format(nitro_instance_private_dns, 443), context=ssl_context
        )

        try:
            https_nitro_client.request(
                "POST",
                "/sign_hash",
                body=json.dumps({"hash": hash_value, "secret_id": secret_id}),
            )
            response = https_nitro_client.getresponse()
        except Exception as e:
            raise Exception(
                "exception happened sending sign_hash request to Nitro Enclave: {}".format(e)
            )

        response_raw = response.read()
        response_parsed = json.loads(response_raw)

        if "error" in response_parsed:
            raise Exception("Enclave error: {}".format(response_parsed["error"]))

        expected_address = event.get("expected_address")
        if expected_address and "signature" in response_parsed:
            _verify_recovered_address(
                hash_value, response_parsed["signature"], expected_address
            )

        return response_parsed

    else:
        raise ValueError("operation: {} not supported right now".format(operation))
