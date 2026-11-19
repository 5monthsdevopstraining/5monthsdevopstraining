#!/usr/bin/env bash
# Safely removes the development environment.
# 1) Deletes the Kubernetes Ingress first, so the AWS Load Balancer Controller removes the
#    ALB and its security groups (Terraform does not know about them and the VPC delete
#    would fail otherwise).
# 2) Runs terraform destroy after you confirm.
# Run from the repository root:   bash scripts/cleanup.sh
set -euo pipefail

cd "$(dirname "$0")/../terraform"
export AWS_PROFILE="${AWS_PROFILE:-dotnet8-dev}"

echo "This will DESTROY the whole environment: EKS, Jenkins, RDS (and its data), the S3 bucket, and ECR images."
read -r -p "Type 'destroy' to continue: " ANSWER
[ "$ANSWER" = "destroy" ] || { echo "Stopped. Nothing was deleted."; exit 0; }

REGION="$(terraform output -raw aws_region)"
CLUSTER="$(terraform output -raw eks_cluster_name)"
JENKINS_ID="$(terraform output -raw jenkins_instance_id)"
NAMESPACE="$(terraform output -raw kubernetes_namespace)"

echo "== Step 1: delete the Ingress (and so the ALB) through the Jenkins server"
CMD_ID="$(aws ssm send-command \
  --region "$REGION" \
  --instance-ids "$JENKINS_ID" \
  --document-name "AWS-RunShellScript" \
  --comment "cleanup ingress before terraform destroy" \
  --parameters "commands=[\"sudo -u jenkins -H bash -c 'export KUBECONFIG=/tmp/cleanup-kubeconfig; aws eks update-kubeconfig --name $CLUSTER --region $REGION --kubeconfig \$KUBECONFIG && kubectl -n $NAMESPACE delete ingress --all --wait=true --timeout=300s; kubectl delete namespace $NAMESPACE --wait=true --timeout=300s; rm -f \$KUBECONFIG'\"]" \
  --query "Command.CommandId" --output text || true)"

if [ -n "$CMD_ID" ]; then
  echo "SSM command: $CMD_ID (waiting up to ~6 minutes)"
  aws ssm wait command-executed --region "$REGION" --command-id "$CMD_ID" --instance-id "$JENKINS_ID" || true
  aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$JENKINS_ID" \
    --query "{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}" --output json || true
  echo "Waiting 60 seconds for AWS to remove the load balancer..."
  sleep 60
else
  echo "Could not reach the Jenkins server through SSM. If a load balancer named k8s-sampleap-* still exists,"
  echo "delete it in the EC2 console before continuing, otherwise the VPC cannot be deleted."
fi

echo "== Step 2: terraform destroy"
terraform destroy

echo "Done. Double-check the AWS console (EC2, EKS, RDS, VPC) and Billing for leftovers."
