#!/bin/bash
# Log in to the deployer EC2 (docker, kubectl and helm are ready there, kubeconfig is set up by the deploy):
#   ./eks/scripts/ssh.sh                      # interactive shell
#   ./eks/scripts/ssh.sh kubectl get pods -A  # run one command
set -euo pipefail
source "$(dirname "$0")/lib.sh"

remote_ssh "$@"
