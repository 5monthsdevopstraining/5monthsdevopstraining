#!/bin/bash
# Runs ON the private deployer EC2 (started by eks/scripts/deploy.sh through SSM Run Command, as root).
# Steps:
#   0. docker build ./app and push it to ECR (with the EC2's IAM role)
#   1. kubeconfig for the private cluster
#   2. install/upgrade the AWS Load Balancer Controller (Helm)
#   3. create the app ConfigMap (region, S3 bucket, folder)
#   4. kubectl apply k8s/ with the new image, wait for the rollout and the ALB address
# Usage: remote-deploy.sh <region> <cluster> <vpc_id> <s3_bucket> <s3_upload_prefix> <ecr_repo> <tag>
# Expected layout: <dir>/remote-deploy.sh, <dir>/k8s/*.yaml, <dir>/app/Dockerfile
set -euo pipefail
export HOME=/root # SSM Run Command has no HOME; kubectl/helm keep their config there

REGION=$1
CLUSTER=$2
VPC_ID=$3
BUCKET=$4
UPLOAD_PREFIX=$5
ECR_REPO=$6
TAG=$7
IMAGE="$ECR_REPO:$TAG"

ROOT=$(cd "$(dirname "$0")" && pwd)
NAMESPACE=sample-app                 # must match k8s/*.yaml
LBC_SA=aws-load-balancer-controller  # must match local.lbc_service_account in eks/terraform/provider.tf
LBC_CHART_VERSION=3.6.2              # same version as eks/terraform/policies/lb-controller-iam-policy.json

echo "==> Build and push $IMAGE"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${ECR_REPO%%/*}"
docker build -q -t "$IMAGE" "$ROOT/app"
docker push -q "$IMAGE"
docker image prune -f >/dev/null

echo "==> Connect to private cluster $CLUSTER"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" >/dev/null
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
kubectl apply -f "$ROOT/k8s/00-namespace.yaml" -f "$ROOT/k8s/01-serviceaccount.yaml"

# create-or-update (ASP.NET reads "__" as ":" -> S3:BucketName etc.)
kubectl create configmap sample-app-config --namespace "$NAMESPACE" \
  --from-literal=AWS__Region="$REGION" \
  --from-literal=S3__BucketName="$BUCKET" \
  --from-literal=S3__KeyPrefix="$UPLOAD_PREFIX" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Deploy $IMAGE"
sed "s|IMAGE_PLACEHOLDER|$IMAGE|" "$ROOT/k8s/02-deployment.yaml" | kubectl apply -f -
kubectl apply -f "$ROOT/k8s/03-service.yaml" -f "$ROOT/k8s/04-ingress.yaml"

# ConfigMap changes don't restart pods on their own
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

echo "APP_HOST=$HOST" # read by deploy.sh
