import base64
import json
import socket
import subprocess

import boto3


def kms_call(credential, ciphertext):
    aws_access_key_id = credential['access_key_id'],
    aws_secret_access_key = credential['secret_access_key'],
    aws_session_token = credential['token']

    proc = subprocess.Popen(
        [
            "/kmstool_enclave_cli",
            "--region", "us-east-1",
            "--proxy-port", "8000",
            "--aws-access-key-id", aws_access_key_id,
            "--aws-secret-access-key", aws_secret_access_key,
            "--aws-session-token", aws_session_token,
            "--ciphertext", ciphertext,
        ],
        stdout=subprocess.PIPE
    )

    plaintext = proc.communicate()[0].decode()

    # https://github.com/aws/aws-nitro-enclaves-sdk-c/tree/main/bin/kmstool-enclave-cli
    # todo base64 encoded plaintext

    return plaintext


def aws_api_call(credential):
    client = boto3.client(
        'kms',
        region_name='us-east-1',
        aws_access_key_id=credential['access_key_id'],
        aws_secret_access_key=credential['secret_access_key'],
        aws_session_token=credential['token']
    )

    # This is just a demo API call to demonstrate that we can talk to AWS via API
    response = client.describe_key(
        KeyId=''
    )

    # Return some data from API response
    return {
        'KeyId': response['KeyMetadata']['KeyId'],
        'KeyState': response['KeyMetadata']['KeyState']
    }


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
        credential = payload_json["credential"]
        ciphertext = base64.standard_b64decode(payload_json["ciphertext"])

        # Get data from AWS API call
        content = aws_api_call(credential)

        plaintext = kms_call(credential, ciphertext)

        # Send the response back to parent instance
        c.send(str.encode(json.dumps(content)))

        # Close the connection
        c.close()


if __name__ == '__main__':
    main()
