#!/bin/bash
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

set -x
set +e

yum update -y
systemctl start crond
systemctl enable crond
amazon-linux-extras install docker
systemctl start docker
systemctl enable docker
amazon-linux-extras enable aws-nitro-enclaves-cli
yum install -y aws-nitro-enclaves-cli aws-nitro-enclaves-cli-devel htop git mod_ssl

usermod -aG docker ec2-user
usermod -aG ne ec2-user

ALLOCATOR_YAML=/etc/nitro_enclaves/allocator.yaml
MEM_KEY=memory_mib
CPU_KEY=cpu_count
DEFAULT_MEM=3072
DEFAULT_CPU=2

sed -r "s/^(\s*$MEM_KEY\s*:\s*).*/\1$DEFAULT_MEM/" -i "$ALLOCATOR_YAML"
sed -r "s/^(\s*$CPU_KEY\s*:\s*).*/\1$DEFAULT_CPU/" -i "$ALLOCATOR_YAML"

sleep 20
systemctl start nitro-enclaves-allocator.service
systemctl enable nitro-enclaves-allocator.service

systemctl start nitro-enclaves-vsock-proxy.service
systemctl enable nitro-enclaves-vsock-proxy.service

cd /home/ec2-user
mkdir dev


# todo add as service
#  https://stackoverflow.com/questions/51915848/configure-a-python-as-a-service-in-aws-ec2
if [[ ! -d ./app ]]; then
  mkdir app
  cd ./app
  cat <<'EOF' >>app.py
import sys
import socket
import json
import ssl
import logging
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
            self.wfile.write("ciphertext missing".encode("utf-8")

        call_enclave(16, 5000, ciphertext)

        self._set_response()
        self.wfile.write("POST request for {}".format(self.path).encode('utf-8'))

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
        'access_key_id' : response['AccessKeyId'],
        'secret_access_key' : response['SecretAccessKey'],
        'token' : response['Token']
    }

    return credential

def call_enclave(cid, port, ciphertext):
    # Get EC2 instance metedata
    payload={}
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
    print(s.recv(1024).decode())

    # close the connection
    s.close()


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

EOF

if [[ ! -d ./app/server ]]; then
  mkdir -p ./app/server

  cd ./app/server
  cat <<'EOF' >>build_signing_server_enclave.sh
#!/usr/bin/bash

set -x
set -e

account_id=$( aws sts get-caller-identity | jq -r '.Account' )
region=$( curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region' )
aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $account_id.dkr.ecr.$region.amazonaws.com
docker pull ${__SIGNING_SERVER_IMAGE_URI__}

nitro-cli build-enclave --docker-uri ${__SIGNING_SERVER_IMAGE_URI__} --output-file signing_server.eif

EOF
  chmod +x build_signing_server_enclave.sh
  cd ../..
  chown -R ec2-user:ec2-user ./app

  sudo -H -u ec2-user bash -c "cd /home/ec2-user/app/server && ./build_signing_server_enclave.sh && nitro-cli run-enclave --debug-mode --cpu-count 2 --memory 2500 --eif-path signing_server.eif"
fi

# todo create service entry for watchdog
echo "@reboot ec2-user nitro-cli run-enclave --debug-mode --cpu-count 2 --memory 2500 --eif-path /home/ec2-user/app/server/signing_server.eif" >>/etc/crontab

cd /etc/pki/tls/certs
./make-dummy-cert localhost.crt

python3 /home/ec2-user/app/http_server.py
