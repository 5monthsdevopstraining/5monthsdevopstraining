#!/bin/bash
# Run any kubectl command against the private cluster from your laptop.
# The command is executed over SSH on the deployer EC2 inside the VPC.
#   ./eks/scripts/kubectl.sh get nodes -o wide
#   ./eks/scripts/kubectl.sh get pods -A
#   ./eks/scripts/kubectl.sh logs -n sample-app deployment/sample-app --tail 50
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[ $# -gt 0 ] || { echo "usage: $0 <kubectl args>" >&2; exit 1; }

remote_ssh "kubectl $(printf '%q ' "$@")"
