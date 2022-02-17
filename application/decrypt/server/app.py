import json
import logging
import socket
import ssl
from http import client
from http.server import BaseHTTPRequestHandler, HTTPServer


class S(BaseHTTPRequestHandler):
    def _set_response(self, http_status=200):
        self.send_response(http_status)
        self.send_header('Content-type', 'application/json')
        self.end_headers()

    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        logging.info("POST request,\nPath: %s\nHeaders:\n%s\n\nBody:\n%s\n",
                     str(self.path), str(self.headers), post_data.decode('utf-8'))
        payload = json.loads(post_data.decode('utf-8'))
        # todo enclaveid
        ciphertext = payload.get("ciphertext")
        if not ciphertext:
            self._set_response(404)
            self.wfile.write("ciphertext missing".encode("utf-8"))

        plaintext_json = call_enclave(16, 5000, ciphertext)

        self._set_response()
        self.wfile.write(plaintext_json.encode("utf-8"))


def get_aws_session_token():
    """
    Get the AWS credential from EC2 instance metadata
    """

    http_ec2_client = client.HTTPConnection("169.254.169.254")
    http_ec2_client.request("GET", "/latest/meta-data/iam/security-credentials/")
    r = http_ec2_client.getresponse()

    instance_profile_name = r.read().decode()

    http_ec2_client = client.HTTPConnection("169.254.169.254")
    http_ec2_client.request("GET", "/latest/meta-data/iam/security-credentials/{}".format(instance_profile_name))
    r = http_ec2_client.getresponse()

    response = json.loads(r.read())

    credential = {
        'access_key_id': response['AccessKeyId'],
        'secret_access_key': response['SecretAccessKey'],
        'token': response['Token']
    }

    return credential


def call_enclave(cid, port, ciphertext):
    # Get EC2 instance metedata
    payload = {}
    payload["credential"] = get_aws_session_token()
    payload["ciphertext"] = ciphertext

    # Create a vsock socket object
    s = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)

    # Get CID from command line parameter
    # todo automate via external system call
    # cid = int(sys.argv[1])

    # The port should match the server running in enclave
    # port = 5000

    # Connect to the server
    s.connect((cid, port))

    # Send AWS credential to the server running in enclave
    s.send(str.encode(json.dumps(payload)))

    # receive data from the server
    payload_processed = s.recv(1024).decode()
    print("payload_processed: {}".format(payload_processed))

    # close the connection
    s.close()

    return payload_processed


def run(server_class=HTTPServer, handler_class=S, port=443):
    logging.basicConfig(level=logging.INFO)
    server_address = ('0.0.0.0', port)
    httpd = server_class(server_address, handler_class)
    logging.info('Starting httpd...\n')
    httpd.socket = ssl.wrap_socket(httpd.socket,
                                   server_side=True,
                                   certfile='/etc/pki/tls/certs/localhost.crt',
                                   ssl_version=ssl.PROTOCOL_TLS)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()
    logging.info('Stopping httpd...\n')


if __name__ == '__main__':
    run()
