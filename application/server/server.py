import base64
import json
import socket
import subprocess


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
        ciphertext = payload_json["ciphertext"]

        # Get data from AWS API call
        # content = aws_api_call(credential)

        plaintext = kms_call(credential, ciphertext)
        print("plaintext: {}".format(base64.standard_b64decode(plaintext)))
        # c.send(str.encode(json.dumps(plaintext)))
        # Send the response back to parent instance
        # c.send(str.encode(json.dumps(content)))

        # Close the connection
        c.close()


if __name__ == '__main__':
    main()
