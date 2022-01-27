#!/bin/bash
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

set -x
set +e

if [[ ${__DEV_MODE__} == "dev" ]]; then
  cat <<'EOF' >>/tmp/install_chronicled.py
#!/usr/bin/python2.7

import sys

MIN_PYTHON = (2, 7)
if sys.version_info < MIN_PYTHON:
    sys.exit("Python %s.%s or later is required.\n" % MIN_PYTHON)

import botocore.session
import botocore.auth
import botocore.awsrequest
import errno
import json
import os
import requests
import subprocess
import syslog
import time

# The latest Chronicle version.
# Should be updated with each new Chronicle release
LATEST_CHRONICLE_VERSION = "chronicled-2.0.1092.0-1_naws"

# The aws-sec-informatics RPM signing key.
PUBLIC_KEY = """-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v2

mQINBFzKMpgBEACrasdQqYhqFEV5dNE34FpkY6xZ1RXiplb//aVIGZagkuuhRchU
AwQwWAoVqj4+YUYdObBQmGgu9if1kMTmo4vA7lyjaol/fRNQW7abDbvLUeHObzrz
c5aPvYz5yy4kXM6pTvmFHWDx74+AhUNkklRFDxhpAX5wIBzGnMtQFu0tKezFdwXj
OSCBooDNVKqRXXwi+qwRedhLevGHOLeB3PmUPl4nukEf26IH18UN4WGl5s1SAlei
bD+OkA6Xp5M5FWgmeFcD9YjM7J2tVD80P/4TMwQa9AfYX8yX0jHWSdIyVMcwGsRY
fXMWvt3VkOLFKCOugWCFr6xj+ogHfTXFo0YN9kKKTdBkqgtcdC0HgIEOzdJVsVuO
tQKNjSalzs7tceyqAMW0+zu80TXKXLk6HL41TUY5nptfyWn9sKaWTY74qYAT1WGy
h1Byn+DBFD4BI9uO3CLreDF9oYCcVzPJzAQ4OulvpOuMX3U+J5nMRO0DZeoavFbb
4WpjeobkXB9L2V8tkqNTY1Vn4S/MinpRmUmsQJFjCAG/ZcTejiCJI9mc1/mCcihX
LGOudztnnYkLBbK9Nmux+tE0LRThIcM8F6JnC7Y42fjEn4xnpjpi+C5p5lA80xF2
JVkr+xquoprKasp+/mYEPQX9NwbXzkRKY6S4tJ1bX9H7G6WI7Ynvp6MCJwARAQAB
tDRhd3Mtc2VjLWluZm9ybWF0aWNzIDxhd3Mtc2VjLWluZm9ybWF0aWNzQGFtYXpv
bi5jb20+iQI5BBMBCAAjBQJcyjKYAhsDBwsJCAcDAgEGFQgCCQoLBBYCAwECHgEC
F4AACgkQxsHtsCiC8moNyA/+OadXPTpDE55B9sCQmd0HBRnAN++GJMmxYclLc6Yv
Y9G7sG0b3TaT7KMgr6Mfn73LF59Aq8KfGvydQYuEfp/ig68+G3Bf4/XluPwrywMg
dlWefHfd1pcOkIAQA5hhE1ApviAGDrvJYFGx7o1lj4Aw0QPBFNcVCmWsbV8zY3pa
MuYm+sAA/TQsjtO9RhUi/aShTEBfUVv0pFNMJc5aYNhHnpiJUHpEKgfcYJIjMXsi
zpkngeZoHvULDoPP8CPlHmPvR9zrj5EH1UnBsmvigcK9Dlcl3xv5NwnL7Gv7xMVc
d0Y97nWAqRMpSJW2aJWE5yGSEYivi/VQXFCUdd7I0FNZJg98w2iP69HYV+WKdbxJ
+T45yHGPtFyEYiEuiUt7idJzfE2zx0Wv0j3tVBXsS2w2gKvsRQoP/tdiiqbaTkCz
LJO7szQAu1PrrBzACqNp78EdWUgnFamLD+Fr++VHXemPiDDCisLWuXV/4oS+MMCL
kL1ylOZWbZ+DZ4yBgUMgValIAjfNQ3LZ/XmRY7iOsoPULhHExlkuKk5PzRvNcWnR
mMM/Qm+lzQt+SbU/I2uy9tSLvPHZYlHTy/3OMk7wBVKL2GSY4fUU1f4GiePs6fZT
WZ8WYQO4gb7PBNqz4SDOETE5ntvXrUrg5AaNLBxCtn7K5ExD03bbk2n2HUVRI3YB
z5s=
=+Q8r
-----END PGP PUBLIC KEY BLOCK-----
"""

CHRONICLE_DIR = "/usr/local/chronicle"
RPM_PATH = "/usr/local/chronicle/chronicled.rpm"
KEY_PATH = "/usr/local/chronicle/public_key"


def log(msg):
    print(msg)
    # 80 is LOG_AUTHPRIV
    syslog.syslog(80 | syslog.LOG_ERR, msg)


def log_exit(msg):
    log(msg)
    sys.exit(0)


def decode_output(error):
    # In python 3, the subprocess output is in bytes but is a
    # string in python 2 so we try to convert.
    output = error.output
    try:
        output = output.decode()
    except (UnicodeDecodeError, AttributeError):
        pass
    return output


def get_region():
    # try to use IMDSv2, if it's available
    response = requests.put(
        "http://169.254.169.254/latest/api/token",
        headers = {"X-aws-ec2-metadata-token-ttl-seconds": "21600"}
    )
    headers = {}
    if response.status_code == requests.codes.ok:
        headers["X-aws-ec2-metadata-token"] = response.content

    response = requests.get(
        "http://169.254.169.254/latest/dynamic/instance-identity/document",
        headers = headers
    )
    if response.status_code != requests.codes.ok:
        log_exit(
            "bad response when getting instance-identity document: %s"
            % response.status_code
        )
    data = response.content
    try:
        data = data.decode()
    except (UnicodeDecodeError, AttributeError):
        pass
    return json.loads(data)["region"]


def is_audit_installed():
    try:
        subprocess.check_output(
            ["rpm", "-q", "audit"], stderr=subprocess.STDOUT
        )
        return True
    except subprocess.CalledProcessError:
        return False


def remove_audit():
    # Removing the audit package doesn't always stop the daemon,
    # so do that first.
    subprocess.call(["/sbin/service", "auditd", "stop"])

    try:
        subprocess.check_output(
            ["yum", "-y", "remove", "audit"], stderr=subprocess.STDOUT
        )
    except subprocess.CalledProcessError as e:
        output = decode_output(e)
        log("Unable to remove audit: %s" % output)


def make_dir():
    try:
        os.makedirs(CHRONICLE_DIR, 0o700)
    except OSError as e:
        if e.errno != errno.EEXIST:
            log_exit(str(e))

        # If the directory already exists, just make sure it's got the
        # right mode.
        os.chmod(CHRONICLE_DIR, 0o700)


def attempt_get(retry_count, url, **args):
    attempts = 0
    backoff_factor = 0.2
    while attempts < retry_count:
        attempts += 1
        try:
            results = requests.get(url, **args)
            if results.status_code != requests.codes.ok:
              if results.status_code in [500, 503]:
                time.sleep(4)
                raise Exception('potential throttling, got response code: %s' % results.status_code)
              elif results.status_code > 400:
                raise Exception('unexpected response code: %s' % results.status_code)
            return results
        except Exception as e:
            # Here we want to wait to give the network time to recover
            log(str(e))
            time.sleep(backoff_factor * (2 ** (attempts - 1)))
    # On our last attempt, we want to just pass the request back up the
    # call stack
    return requests.get(url, **args)

def attempt_get_with_fallback(retry_count, reqs, **args):
    for r in reqs[:-1]:
        try:
            return attempt_get(retry_count, r.url, headers=r.headers, **args)
        except Exception as e:
            log(str(e))

    r = reqs[-1]
    return attempt_get(retry_count, r.url, headers=r.headers, **args)


def install_rpm():
    # In order to support pipeline rollbacks, try to downgrade if install
    # comes back with nothing to do.
    for method in ("install", "downgrade"):
        try:
            subprocess.check_output(
                ["yum", "-y", method, RPM_PATH], stderr=subprocess.STDOUT
            )
            return
        except subprocess.CalledProcessError as e:
            output = decode_output(e)
            if "Nothing to do" not in output:
                log_exit("Unable to install chronicle: %s" % output)


def download_rpm():
    # The RPM is stored in a private S3 bucket.  There are too many internal
    # accounts to grant them all access via a bucket policy.  The Chronicle
    # control service has an endpoint that will return a presigned URL to the
    # current RPM, after authenticating and authorizing this account.  This
    # assumes that the EC2 instance has an instance role so we can get its
    # instance credentials.
    arch = os.uname()[4]
    region = get_region()
    if region == "us-iso-east-1":
        remote_hosts = ["https://chronicle-control-prod.%s.c2s.ic.gov" % region]
    elif region == "us-isob-east-1":
        remote_hosts = ["https://chronicle-control-prod.%s.sc2s.sgov.gov" % region]
    elif region == "cn-north-1" or region == "cn-northwest-1":
        # Try the new endpoint, and fallback to the old one in case this
        # gets called inside a VPC that only has the old VPC endpoints setup.
        remote_hosts = [
            "https://control.prod.%s.chronicle.security.aws.a2z.org.cn" % region,
            "https://control.prod.%s.chronicle.security.aws.a2z.com" % region,
        ]
    else:
        remote_hosts = ["https://control.prod.%s.chronicle.security.aws.a2z.com" % region]

    reqs = []
    s = botocore.session.Session()
    for remote_host in remote_hosts:
        url = "%s/rpm/%s.%s.rpm" % (remote_host, LATEST_CHRONICLE_VERSION, arch)
        r = botocore.awsrequest.AWSRequest(method="GET", url=url, data="")
        botocore.auth.SigV4Auth(
            s.get_credentials(), "aws-chronicle-collection", region
        ).add_auth(r)
        p = r.prepare()
        reqs.append(p)

    if region.startswith("us-iso"):
        mvp_ca_bundle = "/etc/pki/%s/certs/ca-bundle.pem" % region
        response = attempt_get_with_fallback(
            5, reqs, verify=mvp_ca_bundle, timeout=10
        )
    else:
        response = attempt_get_with_fallback(5, reqs, timeout=10)

    if response.status_code != requests.codes.ok:
        log_exit("bad response when getting RPM url: %s" % response.status_code)
    presigned_url = response.content

    if region.startswith("us-iso"):
        response = attempt_get(
            5, presigned_url, verify=mvp_ca_bundle, timeout=10
        )
    else:
        response = attempt_get(5, presigned_url, timeout=10)

    if response.status_code != requests.codes.ok:
        log_exit(
            "bad response when getting RPM contents: %s" % response.status_code
        )
    data = response.content

    with open(RPM_PATH, "wb") as outf:
        outf.write(data)


def verify_rpm():
    # Install the public key.
    with open(KEY_PATH, "wb") as outf:
        outf.write(PUBLIC_KEY.encode("utf-8"))
    try:
        subprocess.check_output(
            ["rpm", "--import", KEY_PATH], stderr=subprocess.STDOUT
        )
    except subprocess.CalledProcessError as e:
        output = decode_output(e)
        log_exit("Unable to import public key: %s" % output)

    # Verify that the RPM is signed.
    try:
        sig = subprocess.check_output(
            ["rpm", "-qp", "--qf", "%{SIGPGP:pgpsig}", RPM_PATH]
        )
        # Python3 we need to decode, Python 2 returns a string so we do nothing
        try:
            sig = sig.decode()
        except (UnicodeDecodeError, AttributeError):
            pass
        if "c6c1edb02882f26a" not in sig:
            log_exit("RPM is not signed")
    except subprocess.CalledProcessError as e:
        output = decode_output(e)
        log_exit("Error reading signature from RPM: %s" % output)

    # Verify that the signature is valid.
    try:
        subprocess.check_output(
            ["rpm", "--checksig", RPM_PATH], stderr=subprocess.STDOUT
        )
    except subprocess.CalledProcessError as e:
        output = decode_output(e)
        log_exit("RPM has invalid signature: %s" % output)


def check_rpmdb():
    # We're not going to try a full repair, but we can at least check for
    # stale locks.
    try:
        # If everything is working, this won't fail.
        subprocess.check_output(
            ["rpm", "-q", "rpm"], stderr=subprocess.STDOUT
        )
        return
    except subprocess.CalledProcessError as e:
        output = decode_output(e)
        if 'Thread died in Berkeley DB library' not in output:
            log_exit("error calling rpm: %s" % output)

    # A previous process left locks on the rpmdb.
    # Double check that nothing is currently using it.
    ret = subprocess.call(
        "! fuser -u /var/lib/rpm/* 2>&1 | grep -q '(root)'", shell=True
    )
    if ret != 0:
        time.sleep(20)
        ret = subprocess.call(
            "! fuser -u /var/lib/rpm/* 2>&1 | grep -q '(root)'", shell=True
        )
        if ret != 0:
            # root has one of the file open, so we're not going to risk
            # trying to fix it.
            log_exit("error calling rpm: %s" % output)

    # Nothing is running.  Remove the stale lock files.
    files = os.listdir("/var/lib/rpm")
    for filename in files:
        if filename.startswith("__db"):
            os.remove(os.path.join("/var/lib/rpm",filename))


if __name__ == "__main__":
    try:
        make_dir()
        download_rpm()
        check_rpmdb()

        try:
            verify_rpm()

            if is_audit_installed():
                remove_audit()

            install_rpm()

            log("chronicled installed")

        finally:
            # If the validation failed, make sure we don't leave a bad RPM lying
            # around that an admin could accidentally install.
            os.remove(RPM_PATH)

    except Exception as e:
        # Swallow errors so that we don't block instances from starting if this
        # script has been added to a userdata script that check for errors.
        log_exit("caught exception: %s" % str(e))

EOF

  python /tmp/install_chronicled.py

fi

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

cd /home/ec2-user
mkdir dev

if [[ ! -d ./app ]]; then
  mkdir app
  cd ./app
  cat <<'EOF' >>app.py
import sys
import socket
import requests
import json

def get_aws_session_token():
    """
    Get the AWS credential from EC2 instance metadata
    """
    r = requests.get("http://169.254.169.254/latest/meta-data/iam/security-credentials/")
    instance_profile_name = r.text

    r = requests.get("http://169.254.169.254/latest/meta-data/iam/security-credentials/%s" % instance_profile_name)
    response = r.json()

    credential = {
        'access_key_id' : response['AccessKeyId'],
        'secret_access_key' : response['SecretAccessKey'],
        'token' : response['Token']
    }

    return credential

def main():
    # Get EC2 instance metedata
    credential = get_aws_session_token()

    # Create a vsock socket object
    s = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)

    # Get CID from command line parameter
    cid = int(sys.argv[1])

    # The port should match the server running in enclave
    port = 5000

    # Connect to the server
    s.connect((cid, port))

    # Send AWS credential to the server running in enclave
    s.send(str.encode(json.dumps(credential)))

    # receive data from the server
    print(s.recv(1024).decode())

    # close the connection
    s.close()

if __name__ == '__main__':
    main()

EOF

  cat <<'EOF' >>http_server.py
#!/usr/bin/env python3

import http.server, ssl

server_address = ('0.0.0.0', 443)
httpd = http.server.HTTPServer(server_address, http.server.SimpleHTTPRequestHandler)
httpd.socket = ssl.wrap_socket(httpd.socket,
                               server_side=True,
                               certfile='/etc/pki/tls/certs/localhost.crt',
                               ssl_version=ssl.PROTOCOL_TLS)
httpd.serve_forever()

EOF
  chmod +x http_server.py
  cat <<'EOF' >>index.html
  hello there
EOF

  cd ..
fi

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

echo "@reboot ec2-user nitro-cli run-enclave --debug-mode --cpu-count 2 --memory 2500 --eif-path /home/ec2-user/app/server/signing_server.eif" >>/etc/crontab

cd /etc/pki/tls/certs
sudo ./make-dummy-cert localhost.crt
#chmod  o+r /etc/pki/tls/certs/localhost.crt
