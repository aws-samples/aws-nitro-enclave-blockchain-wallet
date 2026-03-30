#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

import json
import logging
import os
import socket
import ssl
from http import client
from http.server import BaseHTTPRequestHandler, HTTPServer

import boto3

secrets_manager_client = boto3.client(
    service_name="secretsmanager", region_name=os.getenv("REGION", "us-east-1")
)

# Get region for passing to enclave
AWS_REGION = os.getenv("REGION", "us-east-1")


class S(BaseHTTPRequestHandler):
    def _send_json_response(self, data, http_status=200):
        """Send a JSON response with proper Content-Length for TLS compatibility."""
        body = json.dumps(data).encode("utf-8") if isinstance(data, dict) else data.encode("utf-8")
        self.send_response(http_status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.wfile.flush()

    def do_GET(self):
        """Health check endpoint."""
        if self.path == "/health":
            self._send_json_response({"status": "healthy"})
        else:
            self._send_json_response({"error": "Not found"}, 404)

    def do_POST(self):
        content_length = int(self.headers["Content-Length"])
        post_data = self.rfile.read(content_length)

        logging.info("POST request to %s", str(self.path))

        payload = json.loads(post_data.decode("utf-8"))

        if self.path == "/sign_hash":
            self._handle_sign_hash(payload)
        elif self.path == "/sign_transaction" or self.path == "/":
            self._handle_sign_transaction(payload)
        elif self.path == "/generate_key":
            self._handle_generate_key(payload)
        else:
            self._send_json_response({"error": "Unknown endpoint"}, 404)

    def _handle_sign_hash(self, payload):
        """Handle raw hash signing requests."""
        if not payload.get("hash"):
            self._send_json_response({"error": "Missing 'hash' field"}, 400)
            return

        if not payload.get("secret_id"):
            self._send_json_response({"error": "Missing 'secret_id' field"}, 400)
            return

        hash_clean = payload["hash"].replace("0x", "")
        if len(hash_clean) != 64:
            self._send_json_response({"error": "Hash must be 32 bytes (64 hex chars)"}, 400)
            return

        enclave_payload = {
            "operation": "sign_hash",
            "hash": payload["hash"],
            "secret_id": payload["secret_id"],
        }

        result = call_enclave(16, 5000, enclave_payload)
        self._send_json_response(result)

    def _handle_sign_transaction(self, payload):
        """Handle full transaction signing requests."""
        if not (payload.get("transaction_payload") and payload.get("secret_id")):
            self._send_json_response({"error": "transaction_payload or secret_id are missing"}, 400)
            return

        enclave_payload = {
            "operation": "sign_transaction",
            "transaction_payload": payload["transaction_payload"],
            "secret_id": payload["secret_id"],
        }

        result = call_enclave(16, 5000, enclave_payload)
        self._send_json_response(result)

    def _handle_generate_key(self, payload):
        """Handle key generation requests - key is generated inside enclave."""
        key_id = payload.get("key_id")
        if not key_id:
            self._send_json_response({"error": "Missing 'key_id' field"}, 400)
            return

        enclave_payload = {
            "operation": "generate_key",
            "key_id": key_id,
        }

        result = call_enclave_generate(16, 5000, enclave_payload)
        self._send_json_response(result)


def get_encrypted_key(secret_id):
    try:
        encrypted_key = secrets_manager_client.get_secret_value(SecretId=secret_id)
    except Exception as e:
        raise e

    return encrypted_key["SecretString"]


def get_imds_token():
    http_ec2_client = client.HTTPConnection("169.254.169.254")
    headers = {
        "X-aws-ec2-metadata-token-ttl-seconds": "21600"  # Token valid for 6 hours
    }
    http_ec2_client.request("PUT", "/latest/api/token", headers=headers)
    token_response = http_ec2_client.getresponse()
    return token_response.read().decode()


def get_aws_session_token():
    try:
        token = get_imds_token()

        http_ec2_client = client.HTTPConnection("169.254.169.254")
        headers = {"X-aws-ec2-metadata-token": token}

        # Get instance profile name
        http_ec2_client.request(
            "GET",
            "/latest/meta-data/iam/security-credentials/",
            headers=headers
        )
        r = http_ec2_client.getresponse()
        instance_profile_name = r.read().decode()

        # Get credentials
        http_ec2_client.request(
            "GET",
            f"/latest/meta-data/iam/security-credentials/{instance_profile_name}",
            headers=headers
        )
        r = http_ec2_client.getresponse()
        response = json.loads(r.read())
        return {
            "access_key_id": response["AccessKeyId"],
            "secret_access_key": response["SecretAccessKey"],
            "token": response["Token"],
        }

    except Exception as e:
        raise Exception(f"Failed to retrieve instance credentials: {str(e)}")
    finally:
        if 'http_ec2_client' in locals():
            http_ec2_client.close()


def call_enclave(cid, port, enclave_payload):
    secret_id = enclave_payload["secret_id"]
    encrypted_key = get_encrypted_key(secret_id)

    payload = {
        "credential": get_aws_session_token(),
        "encrypted_key": encrypted_key,
        "operation": enclave_payload.get("operation", "sign_transaction"),
        "region": AWS_REGION,
    }

    if enclave_payload.get("transaction_payload"):
        payload["transaction_payload"] = enclave_payload["transaction_payload"]
    if enclave_payload.get("hash"):
        payload["hash"] = enclave_payload["hash"]

    return _send_to_enclave(cid, port, payload)


def call_enclave_generate(cid, port, enclave_payload):
    """Call enclave for key generation - no existing secret needed."""
    payload = {
        "credential": get_aws_session_token(),
        "operation": "generate_key",
        "key_id": enclave_payload["key_id"],
        "region": AWS_REGION,
    }

    return _send_to_enclave(cid, port, payload)


def _send_to_enclave(cid, port, payload):
    """Send payload to enclave via vsock and return response."""
    s = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
    s.settimeout(5)

    s.connect((cid, port))
    s.send(str.encode(json.dumps(payload)))
    s.shutdown(socket.SHUT_WR)

    chunks = []
    while True:
        try:
            chunk = s.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
        except socket.timeout:
            break

    s.close()
    return b"".join(chunks).decode()


def run(server_class=HTTPServer, handler_class=S, port=443):
    logging.basicConfig(level=logging.INFO)
    server_address = ("0.0.0.0", port)
    httpd = server_class(server_address, handler_class)
    logging.info("Starting httpd...\n")

    # Use SSLContext with TLS 1.2+ and modern ciphers
    ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_context.minimum_version = ssl.TLSVersion.TLSv1_2
    ssl_context.set_ciphers(
        "ECDHE+AESGCM:DHE+AESGCM:ECDHE+CHACHA20:DHE+CHACHA20"
    )
    ssl_context.load_cert_chain(certfile="/etc/pki/tls/certs/localhost.crt")
    httpd.socket = ssl_context.wrap_socket(httpd.socket, server_side=True)

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()
    logging.info("Stopping httpd...\n")


if __name__ == "__main__":
    run()
