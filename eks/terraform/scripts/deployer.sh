#!/bin/bash
# User data for the EKS deployer EC2 (Amazon Linux 2023: AWS CLI v2 is preinstalled).
# Installs docker, kubectl, helm, jq, git and Jenkins (with its plugins).
# Jenkins is only enabled here, not started: eks/terraform/jenkins.tf writes its config
# (admin user, pipeline job) over SSH and then starts it.
# eks/terraform/jenkins.tf and deploy.tf wait (over SSH) for /var/lib/eks-deployer-ready.
set -euxo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

KUBECTL_VERSION=v1.37.1 # keep within one minor version of the cluster (kubernetes_version)
HELM_VERSION=v3.21.1
PLUGIN_MANAGER_VERSION=2.16.0 # github.com/jenkinsci/plugin-installation-manager-tool

curl -fsSL -o /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/rpm-stable/jenkins.repo
until dnf install -y docker jq tar gzip git fontconfig java-21-amazon-corretto-headless jenkins; do
  echo "dnf failed, retrying in 10s"; sleep 10
done
systemctl enable --now docker
usermod -aG docker ec2-user # "docker" without sudo after you SSH in
usermod -aG docker jenkins  # Jenkins builds the image

# 2 GB swap: headroom for the .NET build next to Jenkins
if [ ! -f /swapfile ]; then
  dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
  chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
fi

until curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"; do
  echo "kubectl download failed, retrying in 10s"; sleep 10
done
chmod +x /usr/local/bin/kubectl

until curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o /tmp/helm.tgz; do
  echo "helm download failed, retrying in 10s"; sleep 10
done
tar xzf /tmp/helm.tgz -C /tmp && mv /tmp/linux-amd64/helm /usr/local/bin/helm && rm -rf /tmp/helm.tgz /tmp/linux-amd64

# deploy-app.sh is run by Terraform (as root) and by Jenkins: this lock makes them take turns
install -m 0666 /dev/null /var/lib/eks-deploy.lock

########## Jenkins ##########

until curl -fsSL -o /opt/jenkins-plugin-manager.jar \
  "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/${PLUGIN_MANAGER_VERSION}/jenkins-plugin-manager-${PLUGIN_MANAGER_VERSION}.jar"; do
  echo "plugin manager download failed, retrying in 10s"; sleep 10
done

# configuration-as-code: config from casc.yaml | job-dsl: creates the pipeline job
# workflow-aggregator: pipelines | git + github: checkout and the push webhook
until java -jar /opt/jenkins-plugin-manager.jar \
  --war /usr/share/java/jenkins.war \
  --plugin-download-directory /var/lib/jenkins/plugins \
  --plugins configuration-as-code job-dsl workflow-aggregator git github timestamper ws-cleanup; do
  echo "plugin download failed, retrying in 10s"; sleep 10
done
chown -R jenkins:jenkins /var/lib/jenkins

# No setup wizard; read the config written by Terraform; keep the heap small next to the docker build
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf <<'EOF'
[Service]
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false -Xmx1g"
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/casc.yaml"
EOF
systemctl daemon-reload
systemctl enable jenkins

touch /var/lib/eks-deployer-ready
echo "EKS deployer ready"
