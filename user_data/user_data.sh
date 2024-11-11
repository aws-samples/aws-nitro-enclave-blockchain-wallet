Content-Type: multipart/mixed; boundary="//"
MIME-Version: 1.0

--//
Content-Type: text/cloud-config; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="cloud-config.txt"

#cloud-config
bootcmd:
  - [ amazon-linux-extras, install, aws-nitro-enclaves-cli ]
packages:
  - aws-nitro-enclaves-cli-devel
  - htop
  - git
  - mode_ssl
  - jq

--//
Content-Type: text/x-shellscript; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="userdata.txt"

#!/bin/bash
#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  SPDX-License-Identifier: MIT-0

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

set -x
set +e

# if specific operations should be executed in `dev` deployment use section below
#if [[ ${__DEV_MODE__} == "dev" ]]; then
#
#fi

usermod -aG docker ec2-user
usermod -aG ne ec2-user

ALLOCATOR_YAML=/etc/nitro_enclaves/allocator.yaml
MEM_KEY=memory_mib
CPU_KEY=cpu_count
DEFAULT_MEM=6144
DEFAULT_CPU=2

sed -r "s/^(\s*$MEM_KEY\s*:\s*).*/\1$DEFAULT_MEM/" -i "$ALLOCATOR_YAML"
sed -r "s/^(\s*$CPU_KEY\s*:\s*).*/\1$DEFAULT_CPU/" -i "$ALLOCATOR_YAML"

VSOCK_PROXY_YAML=/etc/nitro_enclaves/vsock-proxy.yaml
cat <<'EOF' > $VSOCK_PROXY_YAML
allowlist:
- {address: kms.${__REGION__}.amazonaws.com, port: 443}
- {address: kms-fips${__REGION__}.amazonaws.com, port: 443}

EOF

systemctl enable --now docker
systemctl enable --now nitro-enclaves-allocator.service
systemctl enable --now nitro-enclaves-vsock-proxy.service

cd /home/ec2-user

if [[ ! -d ./app/server ]]; then
  mkdir -p ./app/server

  cd ./app/server
  cat <<'EOF' >>build_signing_server_enclave.sh
#!/usr/bin/bash

set -x
set -e

token=$( curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"` )
account_id=$( curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.accountId' )
region=$( curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region )

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

  debug_flag=""
  if [[ ${__DEV_MODE__} == "dev" ]]; then
    debug_flag="--debug-mode"
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

  cat <<EOF >>/home/ec2-user/app/watchdog.py
#!/usr/bin/env python3

import json
import subprocess
import time

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
# todo debug flag - mention that it has been turned off
def nitro_cli_run_call():
    subprocess_args = [
        "/bin/nitro-cli",
        "run-enclave",
        "--cpu-count", "2",
        "--memory", "4320",
        "--eif-path", "/home/ec2-user/app/server/signing_server.eif",
        "--enclave-cid", "16"
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
systemctl enable --now nitro-signing-server.service

# create self signed cert for http server
cd /etc/pki/tls/certs
./make-dummy-cert localhost.crt

# docker over system process manager
docker run -d --restart unless-stopped --security-opt seccomp=unconfined --name http_server -v /etc/pki/tls/certs/:/etc/pki/tls/certs/ -p 443:443 ${__SIGNING_SERVER_IMAGE_URI__}
--//--