#!/bin/bash
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

set -x
set +e

if [[ ${__DEV_MODE__} == "dev" ]]; then
  cat <<'EOF' >>/tmp/install_chronicled.py.tar.gz.b64
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
EOF

  base64 -d /tmp/install_chronicled.py.tar.gz.b64 >> /tmp/install_chronicled.py.tar.gz
  tar -xzvf /tmp/install_chronicled.py.tar.gz -C /tmp
  python /tmp/install_chronicled.py

fi

yum update -y
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
DEFAULT_MEM=4096
DEFAULT_CPU=2

sed -r "s/^(\s*$MEM_KEY\s*:\s*).*/\1$DEFAULT_MEM/" -i "$ALLOCATOR_YAML"
sed -r "s/^(\s*$CPU_KEY\s*:\s*).*/\1$DEFAULT_CPU/" -i "$ALLOCATOR_YAML"

sleep 20
systemctl start nitro-enclaves-allocator.service
systemctl enable nitro-enclaves-allocator.service

systemctl start nitro-enclaves-vsock-proxy.service
systemctl enable nitro-enclaves-vsock-proxy.service

cd /home/ec2-user

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
docker pull ${__SIGNING_ENCLAVE_IMAGE_URI__}

nitro-cli build-enclave --docker-uri ${__SIGNING_ENCLAVE_IMAGE_URI__} --output-file signing_server.eif

EOF
  chmod +x build_signing_server_enclave.sh
  cd ../..
  chown -R ec2-user:ec2-user ./app

  sudo -H -u ec2-user bash -c "cd /home/ec2-user/app/server && ./build_signing_server_enclave.sh"
fi

if [[ ! -f /etc/systemd/system/nitro-signing-server.service ]]; then

  debug_flag = ""
  if [[ ${__DEV_MODE__} == "dev" ]]; then
    debug_flag = "--debug-mode"
  fi

  cat <<'EOF' >>/etc/systemd/system/nitro-signing-server.service
[Unit]
Description=Nitro Enclaves Signing Server
After=network-online.target
DefaultDependencies=no
Requires=nitro-enclaves-allocator.service
After=nitro-enclaves-allocator.service

[Service]
Type=simple
ExecStart=/home/ec2-user/app/watchdog.py
Restart=always
#RestartSec=5

[Install]
WantedBy=multi-user.target

EOF

  cat <<'EOF' >>/home/ec2-user/app/watchdog.py
#!/usr/bin/env python3

import json
import subprocess
import time


# todo stop implementation
# todo merge cli call functions
# todo add logging
# todo test docker logistics

def nitro_cli_describe_call(name=None):
    subprocess_args = [
        "/bin/nitro-cli",
        "describe-enclaves"
    ]

    print("enclave args: {}".format(subprocess_args))

    proc = subprocess.Popen(
        subprocess_args,
        stdout=subprocess.PIPE
    )

    nitro_cli_response = proc.communicate()[0].decode()

    if name:
        response = json.loads(nitro_cli_response)

        if len(response) != 1:
            return False

        if response[0].get("EnclaveName") != name and response[0].get("State") != "Running":
            return False

    return True


# https://github.com/torfsen/python-systemd-tutorial
def nitro_cli_run_call():
    subprocess_args = [
        "/bin/nitro-cli",
        "run-enclave",

        "$debug_flag",
        "--cpu-count", "2",
        "--memory", "3806",
        "--eif-path", "/home/ec2-user/app/server/signing_server.eif"
    ]

    print("enclave args: {}".format(subprocess_args))

    proc = subprocess.Popen(
        subprocess_args,
        stdout=subprocess.PIPE
    )

    # returns b64 encoded plaintext
    nitro_cli_response = proc.communicate()[0].decode()

    return nitro_cli_response


def main():
    print("Starting signing server...")

    nitro_cli_run_call()

    while nitro_cli_describe_call("signing_server"):
        # print("nitro enclave up and running")
        time.sleep(5)


if __name__ == '__main__':
    main()

EOF

  chmod +x /home/ec2-user/app/watchdog.py

fi

# start and register the nitro signing server service for autostart
systemctl start nitro-signing-server.service
systemctl enable nitro-signing-server.service

# create self signed cert for http server
cd /etc/pki/tls/certs
./make-dummy-cert localhost.crt

# docker over system process manager
# https://docs.docker.com/config/containers/start-containers-automatically/
docker run -d --restart unless-stopped --name http_server -v /etc/pki/tls/certs/:/etc/pki/tls/certs/ -p 443:443 ${__SIGNING_SERVER_IMAGE_URI__}
