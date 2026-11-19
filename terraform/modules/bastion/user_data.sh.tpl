#!/bin/bash
set -euxo pipefail

# 1. Update system and install required packages & Docker
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  jq \
  git \
  gettext-base \
  unzip \
  docker.io \
  docker-compose-v2

# Start and enable Docker
systemctl enable --now docker
usermod -aG docker ubuntu || true

# 2. Install kubectl
curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable-${kubernetes_version}.txt)/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

# 3. Install Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 4. Install AWS CLI v2
if ! command -v aws &> /dev/null; then
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install
  rm -rf /tmp/aws /tmp/awscliv2.zip
fi

# 5. Write cluster & application environment configuration
cat > /etc/eks-env <<'ENVEOF'
export AWS_REGION=${region}
export AWS_DEFAULT_REGION=${region}
export CLUSTER_NAME=${cluster_name}
export VPC_ID=${vpc_id}
export LB_CONTROLLER_ROLE_ARN=${lb_role_arn}
export ALB_SG_ID=${alb_sg_id}
export ALB_NAME=${alb_name}
export APP_PORT=${app_port}
export HEALTH_CHECK_PATH=${health_check_path}
export S3_BUCKET_NAME=${s3_bucket_name}
export RDS_HOST=${rds_host}
export RDS_DB=${rds_db}
export RDS_USER=${rds_user}
export RDS_PASSWORD='${rds_password}'
export ECR_REPOSITORY_URI=${ecr_repository_url}
ENVEOF

# 6. Helper script: Point kubectl at private EKS cluster
cat > /usr/local/bin/connect-eks <<'EOF'
#!/bin/bash
source /etc/eks-env
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
kubectl get nodes -o wide
EOF

# 7. Helper script: Install AWS Load Balancer Controller with Helm
cat > /usr/local/bin/install-alb-controller <<'EOF'
#!/bin/bash
set -e
source /etc/eks-env
helm repo add eks https://aws.github.io/eks-charts
helm repo update

HELM_ARGS=(
  --namespace kube-system
  --set clusterName="$CLUSTER_NAME"
  --set region="$AWS_REGION"
  --set vpcId="$VPC_ID"
  --set serviceAccount.create=true
  --set serviceAccount.name=aws-load-balancer-controller
)

if [ -n "$${LB_CONTROLLER_ROLE_ARN:-}" ]; then
  HELM_ARGS+=(--set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$LB_CONTROLLER_ROLE_ARN")
fi

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller "$${HELM_ARGS[@]}"
kubectl -n kube-system rollout status deployment/aws-load-balancer-controller --timeout=300s
EOF

# 8. Helper script: Substitute environment variables and deploy manifest
cat > /usr/local/bin/deploy-app <<'EOF'
#!/bin/bash
set -e
source /etc/eks-env
envsubst '$ALB_SG_ID $ALB_NAME $APP_PORT $HEALTH_CHECK_PATH $AWS_REGION $S3_BUCKET_NAME $RDS_HOST $RDS_DB $RDS_USER $RDS_PASSWORD' < "$${1:-app.yaml}" | kubectl apply -f -
EOF

chmod +x /usr/local/bin/connect-eks /usr/local/bin/install-alb-controller /usr/local/bin/deploy-app

# 9. Install Jenkins with Pipeline support using Docker Compose
mkdir -p /opt/jenkins
cat > /opt/jenkins/Dockerfile <<'DOCKERFILE'
FROM jenkins/jenkins:lts-jdk17
USER root
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    gettext-base \
    jq \
    git \
    unzip \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update && apt-get install -y docker-ce-cli \
    && curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl \
    && curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip -q awscliv2.zip && ./aws/install && rm -rf aws awscliv2.zip \
    && rm -rf /var/lib/apt/lists/*
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
USER jenkins
DOCKERFILE

cat > /opt/jenkins/plugins.txt <<'PLUGINS'
workflow-aggregator
git
pipeline-stage-view
PLUGINS

cat > /opt/jenkins/docker-compose.yml <<'COMPOSE'
services:
  jenkins:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: jenkins
    restart: unless-stopped
    ports:
      - "8080:8080"
    group_add:
      - "$${DOCKER_GID:-999}"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/jenkins_home:/var/jenkins_home
      - /etc/eks-env:/etc/eks-env:ro
COMPOSE

mkdir -p /var/jenkins_home
chown -R 1000:1000 /var/jenkins_home
if docker container inspect jenkins >/dev/null 2>&1; then
  docker rm -f jenkins
fi

DOCKER_GID="$(stat -c '%g' /var/run/docker.sock)" \
  docker compose -f /opt/jenkins/docker-compose.yml up -d --build

echo "Bastion bootstrap complete. Jenkins is running on port 8080."
