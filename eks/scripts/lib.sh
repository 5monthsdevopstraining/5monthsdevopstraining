#!/bin/bash
# Shared helpers for ssh.sh / kubectl.sh (run on your laptop).
# Reads the Terraform outputs of eks/terraform and connects to the deployer EC2 over SSH.

TF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)

# The AWS provider is built with ML-KEM TLS key exchange switched off (DefaultGODEBUG=tlsmlkem=0).
# Some networks (seen on Jio) stall TLS handshakes without it, so terraform hangs on STS:GetCallerIdentity.
export GODEBUG=${GODEBUG:-tlsmlkem=1}

tf_out() {
  terraform -chdir="$TF_DIR" output -raw "$1"
}

HOST=$(tf_out deployer_public_ip)
KEY=$(tf_out deployer_key_file)

# The host key changes every time the instance is replaced, so don't pin it in ~/.ssh/known_hosts
SSH_OPTS=(-i "$KEY" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

# remote_ssh [ssh args...] - ssh to ec2-user on the deployer
remote_ssh() {
  ssh "${SSH_OPTS[@]}" "ec2-user@$HOST" "$@"
}
