import logging
import os
import ssl
from http import client

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


def lambda_handler(event, context):
    _logger.debug("incoming event: {}".format(event))

    nitro_instance_private_dns = os.getenv("NITRO_INSTANCE_PRIVATE_DNS")
    if not nitro_instance_private_dns:
        _logger.fatal("NITRO_INSTANCE_PRIVATE_DNS environment variable not set")

    https_nitro_client = client.HTTPSConnection("{}:{}".format(nitro_instance_private_dns, 443),
                                                context=ssl_context)
    https_nitro_client.request("GET", "/")
    response = https_nitro_client.getresponse()

    _logger.debug("response: {} {}".format(response.status, response.reason))
    _logger.debug("response data: {}".format(response.read()))
