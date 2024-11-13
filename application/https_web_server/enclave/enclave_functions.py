#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

import subprocess as sp  # nosec B404
import threading
import os
import sys
import socket
import time
import json
import logging
import base64
import errno

from typing import List, Optional, Tuple

def start_vsock_proxy(dock_socket: socket.socket) -> None:
    thread = threading.Thread(target=server, args=[dock_socket])
    thread.start()


def server(dock_socket: socket.socket) -> None:
    try:
        while True:
            (server_socket, address) = dock_socket.accept()
            client_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            client_socket.connect(("", 9001))

            outgoing_thread = threading.Thread(
                target=forward, args=(client_socket, server_socket)
            )
            incoming_thread = threading.Thread(
                target=forward, args=(server_socket, client_socket)
            )

            outgoing_thread.start()
            incoming_thread.start()
    finally:
        new_thread = threading.Thread(target=server, args=[dock_socket])
        new_thread.start()


def forward(source: socket.socket, destination: socket.socket) -> None:
    string = " "
    while string:
        string = source.recv(1024)
        if string:
            destination.sendall(string)
        else:
            try:
                source.shutdown(socket.SHUT_RD)
                destination.shutdown(socket.SHUT_WR)
            except socket.error as e:
                # race condition
                if e.errno != errno.ENOTCONN:
                    raise


def handle_response(sock: socket, msg: dict, status: int) -> None:
    response = {"body": msg, "status": status}

    sock.send(str.encode(json.dumps(response)))
    sock.close()


def recvall(s: socket.socket) -> bytes:
    data = bytearray()
    buf_size = 4096
    while True:
        packet = s.recv(buf_size)
        data.extend(packet)
        if len(packet) < buf_size:
            break
    return data
