#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

import socket
import threading
import time
import logging
import os
import errno

def server(local_port, remote_cid, remote_port):
    try:
        dock_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        dock_socket.bind(("", local_port))
        dock_socket.listen(128)

        while True:
            client_socket, addr = dock_socket.accept()

            server_socket = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
            server_socket.connect((remote_cid, remote_port))

            outgoing_thread = threading.Thread(
                target=forward, args=(client_socket, server_socket)
            )
            incoming_thread = threading.Thread(
                target=forward, args=(server_socket, client_socket)
            )

            outgoing_thread.start()
            incoming_thread.start()
    except Exception as e:
        print(e)
    finally:
        new_thread = threading.Thread(
            target=server, args=(local_port, remote_cid, remote_port)
        )
        new_thread.start()


def forward(source, destination):
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


def run(local_port, enclave_cid, enclave_port):
    thread = threading.Thread(
        target=server, args=(local_port, enclave_cid, enclave_port)
    )
    thread.start()

    while True:
        time.sleep(60)


if __name__ == "__main__":
    print("starting vsock proxy")
    run(4443, 16, 5000)
