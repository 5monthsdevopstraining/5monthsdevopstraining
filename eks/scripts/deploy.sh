#!/bin/bash
# Build the sample .NET app and deploy it to the private EKS cluster.
# Run from your laptop after "terraform apply" in eks/terraform
# (no docker or kubectl needed where you run it - the private deployer EC2 does that work):
#   ./eks/scripts/deploy.sh            # image tag = timestamp
#   ./eks/scripts/deploy.sh v2         # custom image tag
# Steps:
#   1. copy app/ + eks/k8s + remote-deploy.sh to S3
#   2. run remote-deploy.sh on the private deployer EC2 via SSM (inside the VPC):
#      docker build + push to ECR, AWS Load Balancer Controller, ConfigMap, Deployment, Service, Ingress (ALB)
#   3. wait until the app answers through the ALB
set -euo pipefail

EKS_DIR=$(cd "$(dirname "$0")/.." && pwd)
REPO_ROOT=$(cd "$EKS_DIR/.." && pwd)
source "$EKS_DIR/scripts/lib.sh"

TAG=${1:-$(date +%Y%m%d-%H%M%S)}
ECR_REPO=$(tf_out ecr_repository_url)
VPC_ID=$(tf_out vpc_id)
BUCKET=$(tf_out s3_bucket)
UPLOAD_PREFIX=$(tf_out s3_upload_prefix)
DEPLOY_PREFIX=$(tf_out s3_deploy_prefix)

echo "==> 1. Upload app source and manifests to s3://$BUCKET/$DEPLOY_PREFIX/"
aws s3 sync "$REPO_ROOT/app" "s3://$BUCKET/$DEPLOY_PREFIX/app" --delete --only-show-errors \
  --exclude "bin/*" --exclude "obj/*" --exclude ".vs/*"
aws s3 sync "$EKS_DIR/k8s" "s3://$BUCKET/$DEPLOY_PREFIX/k8s" --delete --only-show-errors
aws s3 cp "$EKS_DIR/scripts/remote-deploy.sh" "s3://$BUCKET/$DEPLOY_PREFIX/remote-deploy.sh" --only-show-errors

wait_for_deployer

echo "==> 2. Build + deploy on the private deployer (first run ~5-8 min, output appears at the end)"
OUTPUT=$(run_remote "set -e
rm -rf /opt/eks-deploy
aws s3 cp --recursive --only-show-errors s3://$BUCKET/$DEPLOY_PREFIX /opt/eks-deploy --region $REGION
bash /opt/eks-deploy/remote-deploy.sh $REGION $CLUSTER $VPC_ID $BUCKET $UPLOAD_PREFIX $ECR_REPO $TAG" 1800) || {
  echo "$OUTPUT"
  exit 1
}
echo "$OUTPUT"

HOST=$(sed -n 's/^APP_HOST=//p' <<<"$OUTPUT" | tail -1)
[ -n "$HOST" ] || { echo "No ALB hostname in the output" >&2; exit 1; }

echo "==> 3. Waiting for http://$HOST (new ALBs need 2-4 minutes for DNS + health checks)"
for _ in $(seq 1 40); do
  if curl -fsS -o /dev/null --max-time 5 "http://$HOST/swagger/index.html"; then
    echo
    echo "App is up:"
    echo "  Swagger UI : http://$HOST/swagger"
    echo "  Upload     : curl -F file=@README.md http://$HOST/api/files/upload"
    exit 0
  fi
  printf '.'
  sleep 15
done
echo
echo "ALB not answering yet - try http://$HOST/swagger again in a few minutes, or check:" >&2
echo "  ./eks/scripts/kubectl.sh describe ingress sample-app -n sample-app" >&2
exit 1
