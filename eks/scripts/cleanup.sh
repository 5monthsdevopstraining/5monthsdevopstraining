#!/bin/bash
# Delete everything (EKS is billed per hour).
# 1. delete the Ingress first, so the AWS Load Balancer Controller removes the ALB and its security
#    groups (Terraform doesn't know about them, they would block deleting the VPC)
# 2. terraform destroy
set -euo pipefail
EKS_DIR=$(cd "$(dirname "$0")/.." && pwd)
source "$EKS_DIR/scripts/lib.sh"

echo "==> Deleting the Ingress (removes the ALB)"
run_remote "$REMOTE_KUBE_ENV; kubectl delete ingress sample-app -n sample-app --ignore-not-found --wait --timeout 5m" 400 ||
  echo "Could not delete the Ingress - check the EC2 console for a 'sampleapp-eks' load balancer after destroy" >&2

echo "==> terraform destroy"
terraform -chdir="$TF_DIR" destroy
