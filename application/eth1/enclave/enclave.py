#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

import base64
import json
import socket
import time
from enclave_functions import start_vsock_proxy


def main():
    # _logger.info("Starting server...")

    # init status initially false
    init_state = False

    # Create a vsock socket object
    s = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)

    # Listen for connection from any CID
    cid = socket.VMADDR_CID_ANY

    # The port should match the client running in parent EC2 instance
    port = 5000

    # Bind the socket to CID and port
    s.bind((cid, port))

    # Listen for connection from client
    s.listen(128)
    
    try:
        start_vsock_proxy(s)
    except Exception as e:
        print(e)

    while True:
        time.sleep(60)


if __name__ == "__main__":
    main()
