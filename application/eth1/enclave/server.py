#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

import base64
import json
import os
import socket
import subprocess

from web3 import Web3

# Initialize Web3 instance
w3 = Web3()


def kms_decrypt(credential, ciphertext, region=None):
    """Decrypt ciphertext using KMS via attestation."""
    region = region or os.getenv("REGION", "us-east-1")
    subprocess_args = [
        "/app/kmstool_enclave_cli",
        "decrypt",
        "--region", region,
        "--proxy-port", "8000",
        "--aws-access-key-id", credential["access_key_id"],
        "--aws-secret-access-key", credential["secret_access_key"],
        "--aws-session-token", credential["token"],
        "--ciphertext", ciphertext,
    ]

    print("Calling kmstool_enclave_cli decrypt")
    proc = subprocess.Popen(subprocess_args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = proc.communicate()

    if proc.returncode != 0:
        raise Exception(f"KMS decrypt failed: {stderr.decode()}")

    # returns "PLAINTEXT: <b64>" format
    result = stdout.decode()
    plaintext_b64 = result.split(":")[1].strip()
    return plaintext_b64


def main():
    print("Starting server...")

    s = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
    cid = socket.VMADDR_CID_ANY
    port = 5000
    s.bind((cid, port))
    s.listen()

    while True:
        c, addr = s.accept()

        # Accumulate chunks until client signals EOF
        chunks = []
        while True:
            chunk = c.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
        payload = b"".join(chunks)
        payload_json = json.loads(payload.decode())

        credential = payload_json["credential"]
        transaction_dict = payload_json["transaction_payload"]
        key_encrypted = payload_json["encrypted_key"]

        try:
            key_b64 = kms_decrypt(credential, key_encrypted,
                                  payload_json.get("region"))
        except Exception as e:
            msg = f"exception happened calling kms binary: {e}"
            print(msg)
            response_plaintext = {"error": msg}

        else:
            key_plaintext = base64.standard_b64decode(key_b64).decode()

            try:
                transaction_dict["value"] = Web3.to_wei(
                    transaction_dict["value"], "ether"
                )
                transaction_signed = w3.eth.account.sign_transaction(
                    transaction_dict, key_plaintext
                )
                response_plaintext = {
                    "transaction_signed": transaction_signed.raw_transaction.hex(),
                    "transaction_hash": transaction_signed.hash.hex(),
                }

            except Exception as e:
                msg = f"exception happened signing the transaction: {e}"
                print(msg)
                response_plaintext = {"error": msg}

            del key_plaintext

        c.send(str.encode(json.dumps(response_plaintext)))
        c.shutdown(socket.SHUT_WR)
        c.close()


if __name__ == "__main__":
    main()
