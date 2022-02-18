import base64
import json
import socket
import subprocess

import web3
from web3.auto import w3


def kms_call(credential, ciphertext):
    aws_access_key_id = credential['access_key_id']
    aws_secret_access_key = credential['secret_access_key']
    aws_session_token = credential['token']

    subprocess_args = [
        "/app/kmstool_enclave_cli",
        "--region", "us-east-1",
        "--proxy-port", "8000",
        "--aws-access-key-id", aws_access_key_id,
        "--aws-secret-access-key", aws_secret_access_key,
        "--aws-session-token", aws_session_token,
        "--ciphertext", ciphertext,
    ]

    print("subprocess args: {}".format(subprocess_args))

    proc = subprocess.Popen(
        subprocess_args,
        stdout=subprocess.PIPE
    )

    # returns b64 encoded plaintext
    plaintext = proc.communicate()[0].decode()

    return plaintext


def main():
    print("Starting server...")

    # Create a vsock socket object
    s = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)

    # Listen for connection from any CID
    cid = socket.VMADDR_CID_ANY

    # The port should match the client running in parent EC2 instance
    port = 5000

    # Bind the socket to CID and port
    s.bind((cid, port))

    # Listen for connection from client
    s.listen()

    while True:
        c, addr = s.accept()

        # Get AWS credential sent from parent instance
        payload = c.recv(4096)
        payload_json = json.loads(payload.decode())
        print("payload json: {}".format(payload_json))

        credential = payload_json["credential"]
        transaction_dict = payload_json["transaction_payload"]
        key_encrypted = payload_json["encrypted_key"]

        try:
            key_b64 = kms_call(credential, key_encrypted)
        except Exception as e:
            msg = "exception happened calling kms binary: {}".format(e)
            print(msg)
            response_plaintext = msg

        else:
            key_plaintext = base64.standard_b64decode(key_b64).decode()

            # transform input
            transaction_dict["value"] = web3.Web3.toWei(transaction_dict["value"], 'ether')

            try:
                transaction_signed = w3.eth.account.sign_transaction(transaction_dict, key_plaintext)
                response_plaintext = {"transaction_signed": transaction_signed.rawTransaction.hex(),
                                      "transaction_hash": transaction_signed.hash.hex()}
            except Exception as e:
                msg = "exception happened signing the transaction: {}".format(e)
                print(msg)
                response_plaintext = msg

        print("response_plaintext: {}".format(response_plaintext))

        c.send(str.encode(json.dumps(response_plaintext)))
        c.close()


if __name__ == '__main__':
    main()
