#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

import base64
import json
import os
import socket
import subprocess

from web3 import Web3
from eth_keys import keys as eth_keys

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


def kms_generate_random(credential, key_id, region=None, num_bytes=32):
    """Generate random bytes using KMS via attestation.
    
    Uses GenerateDataKey which returns both plaintext (for use in enclave)
    and ciphertext (for storage) encrypted under the specified KMS key.
    """
    region = region or os.getenv("REGION", "us-east-1")
    subprocess_args = [
        "/app/kmstool_enclave_cli",
        "genkey",
        "--region", region,
        "--proxy-port", "8000",
        "--aws-access-key-id", credential["access_key_id"],
        "--aws-secret-access-key", credential["secret_access_key"],
        "--aws-session-token", credential["token"],
        "--key-id", key_id,
        "--key-spec", "AES-256",
    ]

    print("Calling kmstool_enclave_cli genkey")
    proc = subprocess.Popen(subprocess_args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = proc.communicate()

    if proc.returncode != 0:
        raise Exception(f"KMS genkey failed: {stderr.decode()}")

    # Parse output - returns PLAINTEXT and CIPHERTEXT
    result = stdout.decode()
    plaintext_b64 = None
    ciphertext_b64 = None
    
    for line in result.strip().split("\n"):
        if line.startswith("PLAINTEXT:"):
            plaintext_b64 = line.split(":", 1)[1].strip()
        elif line.startswith("CIPHERTEXT:"):
            ciphertext_b64 = line.split(":", 1)[1].strip()
    
    if not plaintext_b64 or not ciphertext_b64:
        raise Exception(f"Unexpected genkey output: {result}")
    
    return plaintext_b64, ciphertext_b64


def generate_key(credential, key_id, region=None):
    """Generate a new Ethereum key pair inside the enclave.
    
    Uses KMS GenerateDataKey to get random bytes that are:
    1. Returned as plaintext to the enclave (for deriving address)
    2. Returned as ciphertext (for storage in Secrets Manager)
    
    The plaintext key never leaves the enclave.
    """
    # Get random bytes from KMS - returns both plaintext and encrypted versions
    plaintext_b64, ciphertext_b64 = kms_generate_random(credential, key_id, region)
    
    # Decode the plaintext to get the raw bytes (32 bytes from AES_256)
    private_key_bytes = base64.standard_b64decode(plaintext_b64)
    
    # Validate the key is within secp256k1 curve order
    SECP256K1_ORDER = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
    key_int = int.from_bytes(private_key_bytes, 'big')
    
    if key_int == 0 or key_int >= SECP256K1_ORDER:
        raise Exception("Generated key outside valid range, retry required")
    
    # Derive the Ethereum address
    private_key = eth_keys.PrivateKey(private_key_bytes)
    address = private_key.public_key.to_checksum_address()
    
    # Securely clear the plaintext key from memory
    del private_key_bytes
    del private_key
    del plaintext_b64
    
    return {
        "address": address,
        "encrypted_key": ciphertext_b64,
    }


def sign_hash(key_bytes, hash_hex):
    """Sign a raw 32-byte hash and return r, s, v signature components."""
    hash_clean = hash_hex.replace("0x", "")
    hash_bytes = bytes.fromhex(hash_clean)
    
    private_key = eth_keys.PrivateKey(key_bytes)
    signature = private_key.sign_msg_hash(hash_bytes)
    
    return {
        "r": hex(signature.r),
        "s": hex(signature.s),
        "v": signature.v + 27,
    }


def sign_transaction(key_bytes, transaction_dict):
    """Sign a full EIP-1559 transaction."""
    transaction_dict["value"] = Web3.to_wei(transaction_dict["value"], "ether")
    # web3 sign_transaction accepts bytes or hex for private key
    transaction_signed = w3.eth.account.sign_transaction(transaction_dict, key_bytes)
    return {
        "transaction_signed": transaction_signed.raw_transaction.hex(),
        "transaction_hash": transaction_signed.hash.hex(),
    }


def main():
    print("Starting server...")

    s = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
    cid = socket.VMADDR_CID_ANY
    port = 5000
    s.bind((cid, port))
    s.listen()

    while True:
        c, addr = s.accept()

        payload = c.recv(4096)
        payload_json = json.loads(payload.decode())
        
        operation = payload_json.get("operation", "sign_transaction")
        print(f"Received {operation} request")

        credential = payload_json.get("credential")
        region = payload_json.get("region")
        
        try:
            if operation == "generate_key":
                # Generate new key - no existing encrypted_key needed
                key_id = payload_json["key_id"]
                response_plaintext = generate_key(credential, key_id, region)
            
            else:
                # All other operations need to decrypt an existing key first
                key_encrypted = payload_json["encrypted_key"]
                key_b64 = kms_decrypt(credential, key_encrypted, region)
                # KMS returns raw bytes as base64, decode to get the 32-byte key
                key_bytes = base64.standard_b64decode(key_b64)

                try:
                    if operation == "sign_hash":
                        hash_to_sign = payload_json["hash"]
                        signature = sign_hash(key_bytes, hash_to_sign)
                        response_plaintext = {"signature": signature}
                    
                    elif operation == "sign_transaction":
                        transaction_dict = payload_json["transaction_payload"]
                        response_plaintext = sign_transaction(key_bytes, transaction_dict)
                    
                    else:
                        response_plaintext = {"error": f"Unknown operation: {operation}"}
                finally:
                    del key_bytes

        except Exception as e:
            msg = f"exception during {operation}: {e}"
            print(msg)
            response_plaintext = {"error": msg}

        if "error" in response_plaintext:
            print(f"Request failed: {response_plaintext['error']}")
        else:
            print("Request succeeded")

        c.send(str.encode(json.dumps(response_plaintext)))
        c.close()


if __name__ == "__main__":
    main()
