#!/usr/bin/env bash
# Checks the Terraform code WITHOUT touching AWS: format, init (no backend), validate.
# Run from the repository root:   bash scripts/validate-terraform.sh
set -euo pipefail

cd "$(dirname "$0")/../terraform"

echo "== terraform fmt (rewrites files into the standard style)"
terraform fmt -recursive

echo "== terraform init (downloads providers; no state is created)"
terraform init -backend=false -input=false

echo "== terraform validate (syntax + references)"
terraform validate

echo
echo "Terraform validation passed."
echo "Note: 'validate' does not talk to AWS. Only 'terraform plan' proves the plan works with your account."
