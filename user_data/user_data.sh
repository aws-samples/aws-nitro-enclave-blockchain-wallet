#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

set -x
set +e

yum update -y
amazon-linux-extras install docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user
amazon-linux-extras enable aws-nitro-enclaves-cli
yum install -y aws-nitro-enclaves-cli aws-nitro-enclaves-cli-devel htop git

cd /home/ec2-user
git clone https://github.com/aws/aws-nitro-enclaves-sdk-c.git

cat << EOF > /etc/nitro_enclaves/allocator.yaml
memory_mib: 2048
EOF

cat << EOF >> build_enclave.sh
#!/usr/bin/bash

set -x
set -e

cd aws-nitro-enclaves-sdk-c
docker build --target kmstool-instance -t kmstool-instance -f containers/Dockerfile.al2 .
docker build --target kmstool-enclave -t kmstool-enclave -f containers/Dockerfile.al2 .
sudo nitro-cli build-enclave --docker-uri kmstool-enclave --output-file kmstool.eif

EOF

chmod +x build_enclave.sh
chown ec2-user:ec2-user aws-nitro-enclaves-sdk-c
chown ec2-user:ec2-user build_enclave.sh

# TODO provide python signing enclave
# TODO add enclave build step
