#!/bin/sh

#ifconfig lo 127.0.0.1

# todo region needs to be adjusted
#echo "127.0.0.1   kms.us-east-1.amazonaws.com" >> /etc/hosts
#
#nohup python3 /app/traffic-forwarder.py 443 3 8000 &
python3 /app/server.py