#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

import base64
import json
import os
import socket
import subprocess
import random
import psycopg2

import web3
from web3.auto import w3

suffix = random.randint(0, 9999)
db_name = f"key_storage_{suffix}"

def kms_call(credential, ciphertext):
    aws_access_key_id = credential["access_key_id"]
    aws_secret_access_key = credential["secret_access_key"]
    aws_session_token = credential["token"]

    subprocess_args = [
        "/app/kmstool_enclave_cli",
        "decrypt",
        "--region",
        os.getenv("REGION"),
        "--proxy-port",
        "8000",
        "--aws-access-key-id",
        aws_access_key_id,
        "--aws-secret-access-key",
        aws_secret_access_key,
        "--aws-session-token",
        aws_session_token,
        "--ciphertext",
        ciphertext,
    ]

    print("subprocess args: {}".format(subprocess_args))

    proc = subprocess.Popen(subprocess_args, stdout=subprocess.PIPE)

    # returns b64 encoded plaintext
    result_b64 = proc.communicate()[0].decode()
    plaintext_b64 = result_b64.split(":")[1].strip()

    return plaintext_b64


def connect_rds(host, port, user, password):
    connection = psycopg2.connect(database="key_storage", user=user, password=password,
                                  host=host, port=port)
    # Open a cursor to perform database operations
    cursor = connection.cursor()

    db_create = """CREATE TABLE {}(
                key_id SERIAL PRIMARY KEY,
                key_name VARCHAR (50) UNIQUE NOT NULL,
                key_description VARCHAR (100) NOT NULL);
                """

    cursor.execute(db_create.format(db_name))

    # Make the changes to the database persistent
    connection.commit()

    cursor.execute(
        f"INSERT INTO {db_name}(key_name, key_description) VALUES('master_key','Super important key')")

    cursor.execute(
        f"INSERT INTO {db_name}(key_name, key_description) VALUES('secondary_key','Less important key')")

    cursor.execute(
        f"INSERT INTO {db_name}(key_name, key_description) VALUES('backup_key','Somehow important key')")
    connection.commit()

    cursor.execute(f"SELECT * FROM {db_name};")
    rows = cursor.fetchall()
    connection.commit()

    cursor.close()
    connection.close()

    for row in rows:
        print(row)


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

    try:
        connect_rds(os.getenv("RDS_ENDPOINT_ADDRESS"), os.getenv("RDS_ENDPOINT_PORT"), "admuser", "Welcome1")
    except Exception as e:
        print("exception happened connecting to rds: {}".format(e))

    while True:
        c, addr = s.accept()

        # Get AWS credential sent from parent instance
        payload = c.recv(4096)
        payload_json = json.loads(payload.decode())
        print("payload json: {}".format(payload_json))

        credential = payload_json["credential"]
        transaction_dict = payload_json["transaction_payload"]
        key_encrypted = payload_json["encrypted_key"]

        # kms outbound call
        try:
            key_b64 = kms_call(credential, key_encrypted)
        except Exception as e:
            msg = "exception happened calling kms binary: {}".format(e)
            print(msg)
            response_plaintext = msg

        else:
            key_plaintext = base64.standard_b64decode(key_b64).decode()

            try:
                transaction_dict["value"] = web3.Web3.toWei(
                    transaction_dict["value"], "ether"
                )
                transaction_signed = w3.eth.account.sign_transaction(
                    transaction_dict, key_plaintext
                )
                response_plaintext = {
                    "transaction_signed": transaction_signed.rawTransaction.hex(),
                    "transaction_hash": transaction_signed.hash.hex(),
                }

            except Exception as e:
                msg = "exception happened signing the transaction: {}".format(e)
                print(msg)
                response_plaintext = msg

            # delete internal reference to plain text password
            del key_plaintext

        print("response_plaintext: {}".format(response_plaintext))

        c.send(str.encode(json.dumps(response_plaintext)))
        c.close()


if __name__ == "__main__":
    main()
