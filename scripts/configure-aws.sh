#!/usr/bin/env bash
# Installs the AWS CLI v2 (if missing) and configures the named profile "dotnet8-dev".
# Run it on Ubuntu:   bash scripts/configure-aws.sh
# You type your values locally - nothing is sent anywhere and never share them with anyone.
set -euo pipefail

PROFILE="${AWS_PROFILE_NAME:-dotnet8-dev}"
REGION="${AWS_REGION_NAME:-ap-south-1}"

echo "== 1/4 Checking AWS CLI"
if command -v aws >/dev/null 2>&1; then
  aws --version
else
  echo "AWS CLI not found. Installing AWS CLI v2 (needs sudo)..."
  sudo apt-get update -y
  sudo apt-get install -y curl unzip
  TMP_DIR="$(mktemp -d)"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "$TMP_DIR/awscliv2.zip"
  unzip -q "$TMP_DIR/awscliv2.zip" -d "$TMP_DIR"
  sudo "$TMP_DIR/aws/install"
  rm -rf "$TMP_DIR"
  aws --version
fi

echo
echo "== 2/4 Configuring profile '$PROFILE'"
echo "Choose ONE way to sign in:"
echo "  1) IAM Identity Center (SSO)  <- recommended: short-lived credentials"
echo "  2) IAM user access keys       <- only if you have no SSO; keys are long-lived"
read -r -p "Enter 1 or 2: " CHOICE

if [ "$CHOICE" = "1" ]; then
  aws configure sso --profile "$PROFILE"
  echo "Log in again later with:  aws sso login --profile $PROFILE"
else
  aws configure --profile "$PROFILE"
fi

echo
echo "== 3/4 Setting default region to $REGION for this profile"
aws configure set region "$REGION" --profile "$PROFILE"
aws configure set output json --profile "$PROFILE"

echo
echo "== 4/4 Verifying your identity"
aws sts get-caller-identity --profile "$PROFILE"

echo
echo "Done. Use it with:  export AWS_PROFILE=$PROFILE"
