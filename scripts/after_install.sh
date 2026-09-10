#!/bin/bash
# after_install.sh
# CodeDeploy AfterInstall hook for pocapp-dev
# Runs after appspec.yml has copied index.html and health.html to /var/www/html.
# Installs httpd/php if not already present (skipped on the golden AMI), makes
# sure the SSM agent is enabled and running, then fills in the instance
# metadata placeholders in index.html.

set -euo pipefail

WEB_ROOT="/var/www/html"

# --------------------------------------------------
# Ensure web server is present (no-op if baked into the AMI)
# --------------------------------------------------

if ! command -v httpd &>/dev/null; then
  dnf install -y httpd php
fi

systemctl enable httpd

# --------------------------------------------------
# SSM agent (pre-installed on AL2023, but not always enabled)
# --------------------------------------------------

if ! rpm -q amazon-ssm-agent &>/dev/null; then
  dnf install -y amazon-ssm-agent
fi

systemctl enable amazon-ssm-agent
systemctl restart amazon-ssm-agent

# --------------------------------------------------
# IMDSv2
# --------------------------------------------------

TOKEN=$(curl -sX PUT \
  "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

INSTANCE_ID=$(curl -s \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

AZ=$(curl -s \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

PRIVATE_IP=$(curl -s \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

SERVER_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# --------------------------------------------------
# Template index.html with the live values
# --------------------------------------------------

sed -i \
  -e "s/__INSTANCE_ID__/${INSTANCE_ID}/g" \
  -e "s/__AZ__/${AZ}/g" \
  -e "s/__PRIVATE_IP__/${PRIVATE_IP}/g" \
  -e "s/__SERVER_TIME__/${SERVER_TIME}/g" \
  "${WEB_ROOT}/index.html"

# --------------------------------------------------
# Log
# --------------------------------------------------

echo "pocapp-dev instance ready: id=$INSTANCE_ID az=$AZ ip=$PRIVATE_IP" \
  > /var/log/pocapp-dev-userdata.log

# --------------------------------------------------
# (Re)start web server
# --------------------------------------------------

systemctl restart httpd