#!/usr/bin/env bash
# Guided Terraform deployment with a cost warning and an explicit confirmation.
# Run from the repository root:   bash scripts/deploy.sh
# It never applies anything without you typing "yes".
set -euo pipefail

cd "$(dirname "$0")/../terraform"

if [ ! -f terraform.tfvars ]; then
  echo "terraform/terraform.tfvars not found."
  echo "Create it first:  cp terraform/terraform.tfvars.example terraform/terraform.tfvars  (then edit it)"
  exit 1
fi

PROFILE="${AWS_PROFILE:-dotnet8-dev}"
export AWS_PROFILE="$PROFILE"

echo "== Who am I? (AWS profile: $PROFILE)"
aws sts get-caller-identity

terraform init -input=false
terraform fmt -recursive
terraform validate
terraform plan -input=false -out=tfplan

cat <<'WARN'

=====================  COST WARNING  =====================
Applying this plan creates PAID resources that bill by the hour even when idle:
  EKS control plane, EC2 worker nodes, Jenkins EC2, NAT Gateway, RDS,
  EBS volumes, Application Load Balancer (created later by the controller).
This is NOT free-tier eligible. A rough idea is in docs/COST-ESTIMATE.md.
Destroy everything when you stop learning:  bash scripts/cleanup.sh
==========================================================

Review the plan above (resources to add / change / destroy).
WARN

read -r -p "Type 'yes' to apply this plan, anything else to stop: " ANSWER
if [ "$ANSWER" != "yes" ]; then
  echo "Stopped. Nothing was created. (The saved plan file is terraform/tfplan.)"
  exit 0
fi

terraform apply tfplan
rm -f tfplan

echo
echo "Apply finished. Next steps:"
echo "  terraform -chdir=terraform output"
echo "  Wait ~5 minutes for Jenkins to finish installing, then follow docs/RUNBOOK.md step 14."
