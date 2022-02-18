import base64
import json
import logging
import os
import ssl
from http import client

import boto3

ssl_context = ssl.SSLContext()
ssl_context.verify_mode = ssl.CERT_NONE
# ssl.SSLContext.verify_mode = ssl.VerifyMode.CERT_OPTIONAL


LOG_LEVEL = os.getenv("LOG_LEVEL", "WARNING")
LOG_FORMAT = "%(levelname)s:%(lineno)s:%(message)s"
handler = logging.StreamHandler()

_logger = logging.getLogger("tx_manager_controller")
_logger.setLevel(LOG_LEVEL)
_logger.addHandler(handler)
_logger.propagate = False

client_kms = boto3.client("kms")


def lambda_handler(event, context):
    """
    example requests

    {
      "operation": "decrypt_enclave",
      "ciphertext": "AQICAHj4McjJwtI+YZu0u9LjWmBuyau0WDq3jknNIKZZnJH3QQEBgQ5tMv5hiX1ekQ0BfrQ/AAAAZjBkBgkqhkiG9w0BBwagVzBVAgEAMFAGCSqGSIb3DQEHATAeBglghkgBZQMEAS4wEQQMZahVu8v2NT1ESAyqAgEQgCMj9eMzVI4n8NFcLi/8vF2Gg01PjAMaqWLt+b1EBj0jPB1r2A=="
    }

    {
      "operation": "decrypt_kms",
      "ciphertext": "AQICAHj4McjJwtI+YZu0u9LjWmBuyau0WDq3jknNIKZZnJH3QQEBgQ5tMv5hiX1ekQ0BfrQ/AAAAZjBkBgkqhkiG9w0BBwagVzBVAgEAMFAGCSqGSIb3DQEHATAeBglghkgBZQMEAS4wEQQMZahVu8v2NT1ESAyqAgEQgCMj9eMzVI4n8NFcLi/8vF2Gg01PjAMaqWLt+b1EBj0jPB1r2A=="
    }

    {
      "operation": "encrypt",
      "keyid": "0f24c87a-c8b5-4399-8f3f-95424a01be8a",
      "plaintext": "Welcome1"
    }

    """
    _logger.debug("incoming event: {}".format(event))

    nitro_instance_private_dns = os.getenv("NITRO_INSTANCE_PRIVATE_DNS")
    if not nitro_instance_private_dns:
        _logger.fatal("NITRO_INSTANCE_PRIVATE_DNS environment variable not set")

    operation = event.get("operation")
    if not operation:
        _logger.fatal("request needs to define operation")

    if operation == "encrypt":

        key_id = event.get("keyid")
        plaintext = event.get("plaintext")

        if not (key_id and plaintext):
            _logger.fatal("encrypt request needs to include a keyid and plaintext")

        try:
            response = client_kms.encrypt(
                KeyId=key_id,
                Plaintext=plaintext.encode()
            )
        except Exception as e:
            raise Exception("exception happened sending encryption request to KMS: {}".format(e))

        response_b64 = base64.standard_b64encode(response['CiphertextBlob'])

        return response_b64

    elif operation == "decrypt_kms":

        ciphertext = event.get("ciphertext")

        if not ciphertext:
            _logger.fatal("encrypt request requires ciphertext")

        try:
            response = client_kms.decrypt(
                CiphertextBlob=base64.standard_b64decode(ciphertext)
            )
        except Exception as e:
            raise Exception("exception happened sending decryption request to KMS: {}".format(e))

        _logger.debug("response: {}".format(response))
        response_plain = response["Plaintext"]

        return response_plain

    elif operation == "decrypt_enclave":

        ciphertext = event.get("ciphertext")

        if not ciphertext:
            _logger.fatal("encrypt request requires ciphertext")

        https_nitro_client = client.HTTPSConnection("{}:{}".format(nitro_instance_private_dns, 443),
                                                    context=ssl_context)

        try:
            https_nitro_client.request("POST", "/",
                                       body=json.dumps({"ciphertext": ciphertext}))
            response = https_nitro_client.getresponse()
        except Exception as e:
            raise Exception("exception happened sending decryption request to Nitro Enclave: {}".format(e))

        _logger.debug("response: {} {}".format(response.status, response.reason))
        _logger.debug("response data: {}".format(response.read()))

        return

    elif operation == "get":
        https_nitro_client = client.HTTPSConnection("{}:{}".format(nitro_instance_private_dns, 443),
                                                    context=ssl_context)
        https_nitro_client.request("GET", "/")
        response = https_nitro_client.getresponse()

        _logger.debug("response: {} {}".format(response.status, response.reason))
        _logger.debug("response data: {}".format(response.read()))

    else:
        _logger.fatal("operation: {} not supported right now".format(operation))
