#!/bin/bash
# Installs Docker on Amazon Linux 2023 and runs Jenkins (LTS) in a container
set -euxo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

until dnf install -y docker; do
  echo "dnf failed, retrying in 10s"; sleep 10
done

systemctl enable --now docker
usermod -aG docker ec2-user

# Jenkins data lives here on the host, so it survives container restarts
mkdir -p /opt/jenkins_home
chown 1000:1000 /opt/jenkins_home

until docker pull jenkins/jenkins:lts-jdk21; do
  echo "docker pull failed, retrying in 10s"; sleep 10
done

docker rm -f jenkins || true
docker run -d \
  --name jenkins \
  --restart unless-stopped \
  -p 8080:8080 \
  -v /opt/jenkins_home:/var/jenkins_home \
  jenkins/jenkins:lts-jdk21

# Initial admin password (needed to unlock Jenkins on first login)
until [ -f /opt/jenkins_home/secrets/initialAdminPassword ]; do
  echo "waiting for Jenkins to start..."; sleep 10
done
echo "Jenkins initial admin password: $(cat /opt/jenkins_home/secrets/initialAdminPassword)"
