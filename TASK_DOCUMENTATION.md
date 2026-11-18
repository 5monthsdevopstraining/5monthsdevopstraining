# Jenkins CI/CD Deployment on Amazon EKS

## 1. Task objective

Build an end-to-end AWS deployment pipeline for a .NET application:

1. Provision AWS infrastructure with Terraform.
2. Deploy Jenkins as a Docker container on an EC2 instance.
3. Push application images to Amazon ECR.
4. Deploy the application to a private Amazon EKS cluster.
5. Add private Amazon RDS PostgreSQL and a private Amazon S3 bucket.
6. Store application database and Jenkins credentials in AWS Secrets Manager.
7. Commit the complete implementation to a GitHub branch.

Target AWS region: `ap-south-1`.

Target repository: `5monthsdevopstraining/5monthsdevopstraining`.

Target branch: `manoj-eks-jenkins`.

## 2. Architecture

```text
Developer
   |
   | Git push
   v
GitHub repository
   |
   | Jenkins SCM checkout
   v
EC2 Jenkins host
   |-- Docker
   |-- Jenkins pipeline
   |-- AWS CLI and kubectl
   |-- EC2 IAM role
   |
   +--> Amazon ECR: build and push application image
   |
   +--> Private Amazon EKS: deploy and roll out application
   |
   +--> Amazon RDS PostgreSQL: application database

Amazon S3: versioned encrypted artifact bucket
AWS Secrets Manager: Jenkins and RDS credentials
```

Terraform creates:

- VPC and public/private subnets
- One NAT gateway for private subnet internet access
- EKS cluster and managed node group
- Private EKS API endpoint
- ECR repository
- S3 artifact bucket
- Private PostgreSQL RDS instance
- EC2 bastion with SSM access
- EC2 Jenkins host
- IAM roles and instance profiles
- Security groups
- Secrets Manager secrets

## 3. Prerequisites

Install or confirm:

- AWS CLI 2.32.0 or later
- Terraform 1.5 or later
- Docker
- kubectl
- Git
- Bash or another Linux shell
- A GitHub account with write access to the repository
- AWS permissions to create VPC, EC2, IAM, EKS, ECR, RDS, S3, and Secrets Manager resources

Verify local tools:

```bash
aws --version
terraform --version
docker --version
kubectl version --client
git --version
```

Authenticate with AWS:

```bash
aws login
aws sts get-caller-identity
```

Use a profile other than `default` when required:

```bash
aws login --profile eks-task
export AWS_PROFILE=eks-task
```

Do not put AWS access keys or GitHub tokens in the repository.

## 4. Repository structure

```text
Dockerfile
Dockerfile.jenkins
Jenkinsfile
TASK_DOCUMENTATION.md
jenkins/casc.yaml
k8s/
  deployment.yaml
  service.yaml
modules/
  bastion/
  ecr/
  eks/
  jenkins/
  networking/
  rds/
  s3/
main.tf
variables.tf
outputs.tf
versions.tf
backend.tf
backend.hcl.example
README.md
```

## 5. Clone and create the working branch

```bash
git clone https://github.com/5monthsdevopstraining/5monthsdevopstraining.git
cd 5monthsdevopstraining
git checkout -b manoj-eks-jenkins
```

For SSH authentication:

```bash
git remote set-url origin git@github.com:5monthsdevopstraining/5monthsdevopstraining.git
```

For HTTPS authentication, use GitHub CLI or a PAT configured as a credential-manager credential:

```bash
gh auth login
```

Never commit credentials.

## 6. Configure Terraform remote state

Create an S3 state bucket and enable:

- Bucket versioning
- AES256 or KMS encryption
- Block public access
- S3 native lockfile support

Create `backend.hcl` from the example:

```bash
cp backend.hcl.example backend.hcl
```

Example shape:

```hcl
bucket       = "YOUR-TERRAFORM-STATE-BUCKET"
key          = "eks-dotnet/terraform.tfstate"
region       = "ap-south-1"
encrypt      = true
use_lockfile = true
```

Do not commit `backend.hcl`.

## 7. Review Terraform variables

The defaults are defined in `variables.tf`:

- Region: `ap-south-1`
- Project: `dotnet-app`
- Environment: `dev`
- EKS version: `1.33`
- Node type: `t3.micro`
- Desired nodes: `2`
- Jenkins type: `t3.micro`
- RDS PostgreSQL: `db.t3.micro`
- RDS engine: PostgreSQL 16
- Jenkins web port: `8080`

Before applying, confirm supported EKS versions:

```bash
aws eks describe-cluster-versions --region ap-south-1 \
  --query 'clusterVersions[].clusterVersion' \
  --output table
```

For production, restrict Jenkins access rather than using the default open CIDR:

```hcl
jenkins_allowed_cidr_blocks = ["YOUR_PUBLIC_IP/32"]
```

## 8. Initialize and deploy Terraform

Format and validate:

```bash
terraform fmt -recursive
terraform init -backend-config=backend.hcl
terraform validate
terraform plan -out=tfplan
```

Review the plan. In particular, review:

- EC2 instance types
- RDS cost and retention
- NAT gateway cost
- Public Jenkins security group
- EKS node count
- ECR, S3, Secrets Manager, and IAM resources

Apply:

```bash
terraform apply tfplan
```

The first apply creates the EKS control plane, nodes, RDS, and Jenkins EC2 host. It may take 15 to 30 minutes.

The Jenkins EC2 instance uses a Docker container with a 1 GB swap file and Java heap limits for small instance types.

## 9. Terraform outputs

List outputs:

```bash
terraform output
```

Important outputs:

```bash
terraform output -raw jenkins_url
terraform output -raw ecr_repository_url
terraform output -raw cluster_name
terraform output -raw rds_endpoint
terraform output -raw s3_bucket_name
terraform output -raw ssm_connect_command
terraform output -raw kubeconfig_command
terraform output -raw jenkins_secret_arn
terraform output -raw rds_secret_arn
```

## 10. Read RDS and Jenkins credentials

Read RDS credentials:

```bash
aws secretsmanager get-secret-value \
  --secret-id "$(terraform output -raw rds_secret_arn)" \
  --query SecretString \
  --output text
```

The returned JSON contains `host`, `port`, `dbname`, `username`, and `password`.

Read Jenkins credentials:

```bash
aws secretsmanager get-secret-value \
  --secret-id "$(terraform output -raw jenkins_secret_arn)" \
  --query SecretString \
  --output text
```

The Jenkins user is `admin`. Keep the password secret.

## 11. Jenkins setup

Open the URL returned by:

```bash
terraform output -raw jenkins_url
```

Complete the Jenkins setup:

1. Open the Jenkins login page.
2. Sign in with `admin` and the password from Secrets Manager.
3. Choose **Install suggested plugins**.
4. Install the required additional plugins if they are not already present:
   - Git
   - Pipeline
   - Pipeline: Declarative
   - Pipeline: SCM Step
   - Docker Pipeline
   - Configuration as Code
   - Job DSL
   - Credentials Binding
   - AWS Credentials
5. Restart Jenkins if Jenkins requests a restart.
6. Verify that `dotnet-eks-cicd` exists on the dashboard.

The pipeline job should:

- Use SCM checkout
- Use repository `5monthsdevopstraining/5monthsdevopstraining`
- Checkout branch `*/manoj-eks-jenkins`
- Load `Jenkinsfile`

No AWS access keys are required on Jenkins when Jenkins uses the EC2 instance role.

For Jenkins access from the browser, the EC2 security group must allow TCP `8080` from the administrator's IP.

Production recommendation: use HTTPS through an application load balancer or reverse proxy and restrict Jenkins to a private network or VPN.

## 12. Configure GitHub credentials

Public repositories do not require a GitHub credential for checkout.

For private repositories:

1. Create a fine-grained GitHub personal access token with read access to repository contents.
2. In Jenkins, open **Manage Jenkins > Credentials**.
3. Add a **Username with password** credential.
4. Use the GitHub username and PAT.
5. Assign an ID such as `github-credentials`.
6. Configure the Git SCM checkout or Jenkinsfile credential if the repository is private.

Do not enter the PAT in Terraform, Jenkinsfile, shell scripts, or GitHub source files.

## 13. Application Docker build

The Docker image uses .NET 8.

The repository must contain a `.csproj` file. Update pipeline parameters or defaults if the project is not named `dotnet-app.csproj`.

The default Docker build arguments are:

- `PROJECT_FILE=dotnet-app.csproj`
- `APP_DLL=dotnet-app.dll`

For a local test:

```bash
docker build \
  --build-arg PROJECT_FILE=dotnet-app.csproj \
  --build-arg APP_DLL=dotnet-app.dll \
  -t dotnet-app:test .
docker run --rm -p 8080:8080 \
  -e ASPNETCORE_URLS=http://+:8080 \
  dotnet-app:test
```

Open `http://localhost:8080`.

## 14. Jenkins pipeline stages

The `Jenkinsfile` contains these stages:

### Stage 1: Validate

Checks:

- `.csproj` exists
- AWS CLI exists
- Docker exists
- kubectl exists

### Stage 2: Build and Push

Uses the Jenkins EC2 instance role to:

1. Read the AWS account ID.
2. Describe the ECR repository.
3. Authenticate Docker to ECR.
4. Build the .NET Docker image.
5. Tag it with `build-${BUILD_NUMBER}-${GIT_COMMIT}`.
6. Push it to ECR.

### Stage 3: Deploy to EKS

Uses the EC2 IAM role to:

1. Update `kubeconfig`.
2. Apply `k8s/service.yaml`.
3. Apply `k8s/deployment.yaml`.
4. Update the Deployment image.
5. Wait for the rollout.
6. Print pods and service status.

## 15. Run the pipeline

Open Jenkins:

1. Select `dotnet-eks-cicd`.
2. Select **Build Now**.
3. Open build number `#1`.
4. Select **Console Output**.

Expected pipeline parameters:

```text
AWS_REGION=ap-south-1
ECR_REPOSITORY_NAME=dotnet-app-dev/dotnet-app
EKS_CLUSTER_NAME=dotnet-app-dev-eks
PROJECT_FILE=dotnet-app.csproj
APP_DLL=dotnet-app.dll
```

Change the project or assembly values if the application names differ.

## 16. Jenkins IAM requirements

The EC2 Jenkins role allows:

- ECR authorization and image push/pull operations
- `eks:DescribeCluster`
- `eks:ListClusters`
- SSM managed instance operations
- Secrets Manager read access for Jenkins credentials

EKS access is configured through an EKS access entry for the Jenkins role.

The private EKS API endpoint security group includes the Jenkins security group.

## 17. Verify AWS resources

Verify EKS:

```bash
aws eks update-kubeconfig \
  --name dotnet-app-dev-eks \
  --region ap-south-1

kubectl get nodes
kubectl get pods -A
kubectl get deployment dotnet-app
kubectl rollout status deployment/dotnet-app --timeout=5m
kubectl get service dotnet-app
```

Verify ECR:

```bash
aws ecr describe-repositories \
  --repository-names dotnet-app-dev/dotnet-app \
  --region ap-south-1
```

Verify RDS:

```bash
aws rds describe-db-instances \
  --db-instance-identifier dotnet-app-dev-postgres \
  --region ap-south-1 \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address,Engine]' \
  --output table
```

Verify S3:

```bash
aws s3api get-bucket-versioning \
  --bucket dotnet-app-dev-artifacts

aws s3api get-public-access-block \
  --bucket dotnet-app-dev-artifacts
```

Verify EC2 and Jenkins:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=dotnet-app-dev-jenkins" \
  --region ap-south-1 \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]' \
  --output table
```

Use the Jenkins URL from Terraform output.

## 18. Connect to private resources

For the private EKS endpoint or RDS, use:

- An AWS SSM session to the bastion
- A VPN
- AWS Direct Connect
- Or a host inside the VPC

Start an SSM bastion session:

```bash
aws ssm start-session \
  --target "$(terraform output -raw bastion_instance_id)" \
  --region ap-south-1
```

Use Jenkins SSM:

```bash
aws ssm start-session \
  --target i-00dfaf15f8f10664a \
  --region ap-south-1
```

Replace the Jenkins instance ID with the current Terraform output or EC2 instance ID.

## 19. Common errors

### Jenkins shows HTTP 503

This may mean Jenkins is starting, has a plugin error, or Configuration as Code failed.

Check Docker:

```bash
docker ps -a
docker logs jenkins --tail 100
```

If the Docker command cannot run directly, use SSM.

### Jenkins Configuration as Code failed

Validate `jenkins/casc.yaml`.

The pipeline job syntax must match the installed Job DSL plugin. A working Jenkins setup can start with a minimal CASC file containing only:

```yaml
jenkins:
  systemMessage: "EKS Jenkins CI/CD"
```

Create or update the pipeline job manually in Jenkins if CASC Job DSL blocks are incompatible with the installed plugin version.

### Jenkins container keeps restarting

Check memory and exit state:

```bash
free -m
swapon --show
docker inspect jenkins
docker logs jenkins --tail 100
dmesg | grep -i oom
```

The EC2 host includes swap and a Java heap limit. Also verify that Docker and Jenkins containers have sufficient disk space.

### AWS credentials missing in Terraform

Use AWS login:

```bash
aws login
aws sts get-caller-identity
```

For Terraform commands, export the temporary credentials safely:

```bash
aws configure export-credentials --format env-no-export > /tmp/aws.env
set -a
source /tmp/aws.env
set +a
terraform plan
```

Delete the temporary file after use:

```bash
rm -f /tmp/aws.env
```

Do not commit exported credentials.

### RDS free-tier restriction

Set `backup_retention_period = 0` for the development instance. For production:

- Enable encrypted backups
- Set an appropriate retention period
- Consider Multi-AZ
- Implement final snapshots and restoration testing

### Jenkins EC2 type rejected

In Free Tier accounts, choose an eligible instance type. This project uses `t3.micro` and includes swap for Jenkins.

Always verify eligible types:

```bash
aws ec2 describe-instance-types \
  --filters "Name=free-tier-eligible,Values=true" \
  --region ap-south-1 \
  --query 'InstanceTypes[].InstanceType' \
  --output table
```

### GitHub push authentication failed

For HTTPS:

```bash
gh auth login
git push -u origin manoj-eks-jenkins
```

For SSH:

```bash
git remote set-url origin git@github.com:5monthsdevopstraining/5monthsdevopstraining.git
git push -u origin manoj-eks-jenkins
```

Confirm that the SSH key or GitHub account has repository write access.

### kubectl authentication failed

Update kubeconfig:

```bash
aws eks update-kubeconfig \
  --name dotnet-app-dev-eks \
  --region ap-south-1
```

Confirm that the caller role appears in `aws_eks_access_entry` or use the bastion IAM role that has EKS administrator access.

## 20. Jenkins security hardening

Before production use:

- Restrict Jenkins security group TCP `8080` to VPN or a corporate CIDR
- Place Jenkins behind HTTPS
- Enable Jenkins CSRF protection
- Use an identity provider or SSO
- Use least-privilege IAM for Jenkins
- Enable S3 bucket logging
- Enable RDS backups and Multi-AZ
- Add RDS deletion protection
- Remove `skip_final_snapshot = true`
- Use immutable ECR tags
- Rotate Jenkins and RDS secrets regularly
- Add webhook-triggered builds
- Store Terraform state in an encrypted, access-controlled remote backend
- Use a CI/CD secret for GitHub checkout rather than embedding credentials

## 21. Git commit and push

Review changes:

```bash
git status
git diff
git add -A
git diff --cached --stat
```

Commit:

```bash
git commit -m "Add Jenkins CI/CD with EKS RDS S3 and EC2 Jenkins"
```

Push:

```bash
git push -u origin manoj-eks-jenkins
```

Open a pull request to merge the completed work into `main` after review.

## 22. Cleanup

Destroy Kubernetes-managed load balancers before Terraform destruction:

```bash
kubectl delete -f k8s/
```

Confirm resources that must be preserved:

- RDS snapshots
- S3 objects
- ECR images
- Terraform state
- Jenkins data volume

Destroy the Terraform environment:

```bash
terraform destroy
```

Do not run destroy against shared or production state without approval.

## 23. Final validation checklist

- AWS CLI authenticated
- Terraform plan completed
- EKS cluster active
- EKS nodes ready
- EC2 Jenkins instance running
- Jenkins login page returns HTTP 200
- Jenkins plugin setup completed
- `dotnet-eks-cicd` pipeline exists
- Pipeline branch is `manoj-eks-jenkins`
- Jenkins EC2 IAM role can push to ECR
- Jenkins EC2 IAM role can describe EKS
- ECR repository contains a build image
- EKS Deployment becomes available
- Kubernetes Service is reachable from the VPC
- RDS status is `available`
- RDS is private and accessible only through the VPC CIDR
- RDS password exists in Secrets Manager
- Jenkins password exists in Secrets Manager
- S3 bucket is private
- S3 versioning is enabled
- Git changes are committed
- Branch is pushed to GitHub
- Cleanup plan is understood
