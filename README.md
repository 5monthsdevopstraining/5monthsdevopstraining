# Private EKS application deployment

This repository contains the .NET application, Terraform for the private EKS
infrastructure, and a Jenkins Docker Compose setup for the bastion:

```text
.
├── .github/             # Repository settings (already present on GitHub)
├── app/                 # .NET application and Dockerfile
├── deploy/              # Kubernetes Deployment, Service, and Ingress
├── eks/                 # Reusable EKS Terraform module
├── terraform/           # Terraform root configuration and other modules
├── jenkins/             # Jenkins image and Docker Compose configuration
└── Jenkinsfile          # Jenkins Pipeline (SCM polling every minute)
```

## Configure Jenkins on the bastion

The Jenkins image installs the Pipeline and Git plugins, so a Pipeline job is
available after rebuilding the image. Back up the current Jenkins home before
rebuilding; this Compose setup keeps using `/var/jenkins_home`. On the bastion:

For a bastion created with the earlier bootstrap, use the `jenkins/` files from
this repository (clone it with your GitHub URL or copy the files over). Then:

```bash
sudo tar -czf "$HOME/jenkins-home.tar.gz" -C /var/jenkins_home .
cd /opt/eks-app/jenkins
docker rm -f jenkins 2>/dev/null || true
DOCKER_GID="$(stat -c '%g' /var/run/docker.sock)" docker compose up -d --build
```

Complete Jenkins' initial setup wizard, then create **New Item → Pipeline**.
Choose **Pipeline script from SCM**, select **Git**, provide your GitHub
repository URL and (for a private repository) a Jenkins credential with
read-only access. Set the branch to the branch containing this Jenkinsfile,
and set **Script Path** to `Jenkinsfile`.

The Jenkinsfile polls SCM every minute. Polling only detects repository changes;
it does not push commits. Restrict Jenkins port 8080 to your trusted IP range
and do not commit AWS credentials, database passwords, SSH private keys,
Terraform state, or Terraform plans.

## Deploy

Before the first application run, install the AWS Load Balancer Controller once
from the bastion:

```bash
connect-eks
install-alb-controller
```

Then run the Jenkins Pipeline job. It:

1. Builds `app/Dockerfile`.
2. Pushes build-number and `latest` tags to the ECR repository provisioned by
   Terraform.
3. Applies `deploy/app.yaml` and waits for the EKS rollout.

The bastion instance profile supplies AWS credentials; no access keys belong in
Jenkins or the repo.

If the infrastructure was already created before the ECR resources were added,
review the plan from `terraform` before applying the updated Terraform
configuration. The bastion bootstrap uses `user_data_replace_on_change`; this
change can replace the bastion. Back up Jenkins data first and inspect the plan
for replacement or deletion. Terraform apply may create billable AWS resources.

## Push the project to GitHub

After cloning the repository and copying your project files into it, create the
feature branch, review the files, and push:

```bash
git switch -c akshay-eks
git add .
git status --short
git commit -m "Add private EKS Jenkins deployment"
git push -u origin akshay-eks
```

The root `.gitignore` excludes Terraform state/plans, local Terraform variables,
keys, and .NET build output. Confirm that no credentials or other sensitive
files appear in `git status --short` before committing.
