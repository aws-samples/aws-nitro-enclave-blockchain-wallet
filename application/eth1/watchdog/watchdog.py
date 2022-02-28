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
        "--debug-mode",
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
