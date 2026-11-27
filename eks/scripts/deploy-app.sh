#!/bin/bash
# Builds the app and deploys it to the private EKS cluster. Runs ON the deployer EC2, started by:
#   - Jenkins on every git push (eks/Jenkinsfile), as user jenkins, from its checkout of the repo
#   - "terraform apply" (eks/terraform/deploy.tf) over SSH, as root, from the files copied from your laptop
# Steps:
#   0. docker build app/ and push it to ECR (with the EC2's IAM role)
#   1. kubeconfig for the private cluster
#   2. install/upgrade the AWS Load Balancer Controller (Helm)
#   3. app ConfigMap (region, S3 bucket, folder) + Secret with the RDS connection string
#   4. kubectl apply eks/k8s/ with the new image, wait for the rollout and the ALB address
#   5. wait until the app answers through the ALB
# Usage: deploy-app.sh <image_tag>
# Settings (cluster, ECR, S3, RDS) come from /etc/eks-deploy.env, written by eks/terraform/jenkins.tf.
# Expected layout = the git repo: <root>/app/Dockerfile, <root>/eks/k8s/*.yaml, <root>/eks/scripts/deploy-app.sh
set -euo pipefail
export PATH=/usr/local/bin:$PATH # sudo's secure_path doesn't include it (kubectl, helm)
[ "$(id -u)" = 0 ] && export HOME=/root # kubectl/helm keep their config there when run with sudo

TAG=${1:?usage: deploy-app.sh <image_tag>}

# shellcheck disable=SC1091
source /etc/eks-deploy.env # AWS_REGION CLUSTER VPC_ID BUCKET UPLOAD_PREFIX ECR_REPO RDS_*
REGION=$AWS_REGION
IMAGE="$ECR_REPO:$TAG"

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
APP_DIR=$REPO_ROOT/app
K8S_DIR=$REPO_ROOT/eks/k8s
NAMESPACE=sample-app                 # must match eks/k8s/*.yaml
LBC_SA=aws-load-balancer-controller  # must match local.lbc_service_account in eks/terraform/provider.tf
LBC_CHART_VERSION=3.6.2              # same version as eks/terraform/policies/lb-controller-iam-policy.json

# Terraform and Jenkins may both deploy at the same time: take turns
exec 9>>/var/lib/eks-deploy.lock
echo "==> Waiting for the deploy lock"
flock 9

echo "==> Build and push $IMAGE"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${ECR_REPO%%/*}"
docker build -q -t "$IMAGE" "$APP_DIR"
docker push -q "$IMAGE"
docker image prune -f >/dev/null

echo "==> Connect to private cluster $CLUSTER"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" >/dev/null
# Same kubeconfig for ec2-user, so "kubectl" works right after you SSH in (uses the EC2's IAM role)
if [ "$(id -u)" = 0 ]; then
  sudo -u ec2-user -H aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" >/dev/null
fi
kubectl get nodes -o wide

echo "==> AWS Load Balancer Controller $LBC_CHART_VERSION"
# Its IAM role comes from Pod Identity (eks/terraform/cluster.tf)
helm repo add eks https://aws.github.io/eks-charts --force-update >/dev/null
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --version "$LBC_CHART_VERSION" \
  --set clusterName="$CLUSTER" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=true \
  --set serviceAccount.name="$LBC_SA" \
  --set keepTLSSecret=true \
  --wait --timeout 5m
# The webhook certificate lives in a Secret that the pods read only at startup. Restart them so they
# always serve the certificate the webhook configuration trusts (otherwise: "x509: certificate signed by unknown authority")
kubectl rollout restart deployment/aws-load-balancer-controller --namespace kube-system
kubectl rollout status deployment/aws-load-balancer-controller --namespace kube-system --timeout 3m

echo "==> Namespace, service account, config"
kubectl apply -f "$K8S_DIR/00-namespace.yaml" -f "$K8S_DIR/01-serviceaccount.yaml"

# create-or-update (ASP.NET reads "__" as ":" -> S3:BucketName etc.)
kubectl create configmap sample-app-config --namespace "$NAMESPACE" \
  --from-literal=AWS__Region="$REGION" \
  --from-literal=S3__BucketName="$BUCKET" \
  --from-literal=S3__KeyPrefix="$UPLOAD_PREFIX" \
  --dry-run=client -o yaml | kubectl apply -f -

# RDS: the master password lives in Secrets Manager (created by RDS); the pods get the full
# connection string as ConnectionStrings__Rds from a Kubernetes Secret
DB_SECRET=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$RDS_SECRET_ARN" \
  --query SecretString --output text)
DB_USER=$(jq -r .username <<<"$DB_SECRET")
DB_PASS=$(jq -r .password <<<"$DB_SECRET")
kubectl create secret generic sample-app-db --namespace "$NAMESPACE" \
  --from-literal=ConnectionStrings__Rds="Host=$RDS_HOST;Port=$RDS_PORT;Database=$RDS_DATABASE;Username=$DB_USER;Password=\"$DB_PASS\";SSL Mode=Require" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Deploy $IMAGE"
sed "s|IMAGE_PLACEHOLDER|$IMAGE|" "$K8S_DIR/02-deployment.yaml" | kubectl apply -f -
kubectl apply -f "$K8S_DIR/03-service.yaml" -f "$K8S_DIR/04-ingress.yaml"

# ConfigMap/Secret changes don't restart pods on their own
kubectl rollout restart deployment/sample-app --namespace "$NAMESPACE" >/dev/null

if ! kubectl rollout status deployment/sample-app --namespace "$NAMESPACE" --timeout 5m; then
  kubectl get pods --namespace "$NAMESPACE" -o wide
  kubectl describe pods --namespace "$NAMESPACE" -l app=sample-app | tail -40
  exit 1
fi
kubectl get pods --namespace "$NAMESPACE" -o wide

echo "==> Waiting for the ALB address"
HOST=""
for _ in $(seq 1 30); do
  HOST=$(kubectl get ingress sample-app --namespace "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  [ -n "$HOST" ] && break
  sleep 10
done
if [ -z "$HOST" ]; then
  echo "Ingress has no ALB yet:"
  kubectl describe ingress sample-app --namespace "$NAMESPACE"
  kubectl logs --namespace kube-system deployment/aws-load-balancer-controller --tail 30
  exit 1
fi
kubectl get ingress --namespace "$NAMESPACE"

echo "==> Waiting for http://$HOST (new ALBs need 2-4 minutes for DNS + health checks)"
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
echo "ALB not answering yet - try http://$HOST/swagger again in a few minutes, or check:"
echo "  ./eks/scripts/kubectl.sh describe ingress sample-app -n sample-app"
# Not a failure: the app is deployed, only DNS/health checks are still settling
