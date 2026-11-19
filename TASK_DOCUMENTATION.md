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
app/
  Controllers/
    DatabaseController.cs
    FilesController.cs
  appsettings.json
  dotnet.csproj
  Program.cs
jenkins/casc.yaml
k8s/
  deployment.yaml
  service.yaml
  serviceaccount.yaml
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

## 13. Application Architecture & Docker build

The application is a .NET 8 Web API providing dual integration with Amazon S3 and Amazon RDS PostgreSQL.

### Application Dependencies

Defined in `app/dotnet.csproj`:
* `AWSSDK.S3` (4.0.104.8): S3 document uploads and downloads.
* `AWSSDK.SecurityToken` (4.1.0.2): AWS STS runtime dependency required for EKS IAM Roles for Service Accounts (IRSA) web identity authentication.
* `Npgsql` (10.0.3): High-performance PostgreSQL database provider.
* `Swashbuckle.AspNetCore` (10.3.1): OpenAPI / Swagger UI interactive documentation.

### API Endpoints

1. **`GET /api/database/connection`**:
   Checks whether the configured PostgreSQL RDS database accepts connections (`SELECT 1`).
2. **`POST /api/files/upload`**:
   Accepts multipart file uploads (up to 10 MB).
   * Validates file size and type.
   * Uploads object to S3 bucket `dotnet-app-dev-artifacts` under key prefix `training-uploads/`.
   * Automatically creates PostgreSQL table `uploaded_files` if not present.
   * Inserts metadata (`id`, `file_name`, `s3_bucket_name`, `s3_object_key`, `content_type`, `file_size`, `uploaded_at`) into PostgreSQL.
   * **Compensating Rollback:** If the database insertion fails, the uploaded S3 object is immediately deleted to prevent orphaned data.
3. **`GET /api/files`**:
   Queries PostgreSQL and returns a list of all uploaded documents.
4. **`GET /api/files/{id}`**:
   Finds the document metadata in PostgreSQL and streams the original file back from S3.
5. **`GET /swagger/index.html`**:
   Interactive Swagger UI.

### Multi-stage Docker Build

The build uses `Dockerfile`:
* **Stage 1 (Build):** `mcr.microsoft.com/dotnet/sdk:8.0` restores dependencies and compiles the application (`dotnet publish` in Release mode).
* **Stage 2 (Runtime):** `mcr.microsoft.com/dotnet/aspnet:8.0` provides a lightweight, secure ASP.NET Core runtime image exposing port 8080.

Build and test locally:

```bash
docker build \
  --build-arg PROJECT_FILE=app/dotnet.csproj \
  --build-arg APP_DLL=dotnet.dll \
  -t dotnet-app:test .
docker run --rm -p 8080:8080 \
  -e ASPNETCORE_URLS=http://+:8080 \
  dotnet-app:test
```

## 14. Jenkins pipeline stages

The `Jenkinsfile` automates the entire CI/CD lifecycle across three declarative stages:

### Stage 1: Validate

Verifies prerequisite CLI tools and configuration inside the Jenkins container:
* Project file `app/dotnet.csproj` existence
* `aws` CLI availability
* `docker` CLI and daemon socket reachability
* `kubectl` binary availability

### Stage 2: Build and Push

Uses the Jenkins EC2 IAM role:
1. Obtains the caller AWS Account ID and describes the ECR repository.
2. Authenticates Docker to Amazon ECR (`aws ecr get-login-password`).
3. Determines the short commit hash (`git rev-parse --short=12 HEAD`).
4. Builds the container image tagged as `build-${BUILD_NUMBER}-${GIT_COMMIT_SHORT}`.
5. Pushes the Docker image to Amazon ECR.
6. Writes the image URI to `.image-uri` for downstream stages.

### Stage 3: Deploy to EKS

Deploys the workload to the private Amazon EKS cluster:
1. Updates `kubeconfig` for cluster `dotnet-app-dev-eks`.
2. **Secrets Manager Integration:** Dynamically fetches database credentials from AWS Secrets Manager (`dotnet-app-dev-postgres-credentials`), parses host, port, dbname, username, and password using `jq`, and creates/updates the Kubernetes Secret `dotnet-app-db` with the connection string. No passwords exist in source code or manifests.
3. Applies `k8s/serviceaccount.yaml` to configure IAM Roles for Service Accounts (IRSA).
4. Applies `k8s/service.yaml` to expose the application via LoadBalancer.
5. Applies `k8s/deployment.yaml` with container port 8080, readiness/liveness probes, and resource limits.
6. Sets the new container image (`kubectl set image deployment/dotnet-app dotnet-app=${IMAGE_URI}`).
7. Verifies rollout completion (`kubectl rollout status deployment/dotnet-app --timeout=5m`).
8. Logs the status of active pods and services.

### Post-Build Cleanup

Deletes the locally cached Docker image on the Jenkins host to conserve disk space on small instances.

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

## 16. IAM Roles and Security Policies

### A. Jenkins EC2 Instance Role (`dotnet-app-dev-jenkins`)
The Jenkins EC2 role is granted least-privilege IAM permissions required for the CI/CD pipeline:
- ECR authentication and image push/pull operations (`ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`).
- EKS cluster discovery (`eks:DescribeCluster`, `eks:ListClusters`).
- EKS cluster API access configured via EKS Access Entry (`aws_eks_access_entry` with `AmazonEKSClusterAdminPolicy`).
- AWS Secrets Manager read access (`secretsmanager:GetSecretValue`) for retrieving RDS database credentials (`dotnet-app-dev-postgres-credentials`).
- AWS Systems Manager (SSM) agent management (`AmazonSSMManagedInstanceCore`).
- Security Group ingress rule allowing Jenkins EC2 to reach the private EKS API endpoint on port 443.

### B. Application Pod IAM Role via IRSA (`dotnet-app-dev-eks-app-s3`)
To avoid baking static AWS IAM access keys into containers or Kubernetes manifests, the application pod uses AWS IAM Roles for Service Accounts (IRSA):
1. **OIDC Provider:** The EKS cluster has an associated OpenID Connect (OIDC) identity provider:
   `oidc.eks.ap-south-1.amazonaws.com/id/D89AE818788D75EEBC68D5D2DA53C67C`
2. **IAM Trust Policy:** Allows the specific Kubernetes ServiceAccount `system:serviceaccount:default:dotnet-app` to assume the role via `sts:AssumeRoleWithWebIdentity`:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::123806349463:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/D89AE818788D75EEBC68D5D2DA53C67C"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": {
             "oidc.eks.ap-south-1.amazonaws.com/id/D89AE818788D75EEBC68D5D2DA53C67C:sub": "system:serviceaccount:default:dotnet-app",
             "oidc.eks.ap-south-1.amazonaws.com/id/D89AE818788D75EEBC68D5D2DA53C67C:aud": "sts.amazonaws.com"
           }
         }
       }
     ]
   }
   ```
3. **IAM Permissions Policy:** Restricts S3 actions exclusively to the application bucket:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
         "Resource": "arn:aws:s3:::dotnet-app-dev-artifacts/*"
       },
       {
         "Effect": "Allow",
         "Action": ["s3:ListBucket"],
         "Resource": "arn:aws:s3:::dotnet-app-dev-artifacts"
       }
     ]
   }
   ```
4. **Kubernetes ServiceAccount (`k8s/serviceaccount.yaml`):**
   ```yaml
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: dotnet-app
     namespace: default
     annotations:
       eks.amazonaws.com/role-arn: arn:aws:iam::123806349463:role/dotnet-app-dev-eks-app-s3
   ```
5. **Runtime Token Exchange:** Kubernetes projects an OIDC web identity token into `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`. The .NET AWS SDK uses `AWSSDK.SecurityToken` to exchange this token with AWS STS for temporary credentials without requiring AWS credentials stored on the filesystem.

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

## 18A. Access the application by AWS LoadBalancer DNS

Retrieve the AWS LoadBalancer hostname:

```bash
kubectl get service dotnet-app
```

Example DNS name:

```text
a15cceb66e8324548bab98dce3caa0f8-1354676405.ap-south-1.elb.amazonaws.com
```

Use the DNS directly instead of `localhost:8081`:

```bash
curl http://<LOAD_BALANCER_DNS>
```

Open the same URL in a browser only from a network that can reach the private VPC.

The Kubernetes Service is currently configured as internet-facing:

```yaml
metadata:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
```

Keep the internet-facing scheme only when public access is required. Internet-facing LoadBalancers can be reached directly from the public internet.

To return to an internal LoadBalancer, change the annotation to:

```yaml
metadata:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-scheme: internal
```

Internet-facing exposure is not enabled by default. Before enabling it, review public authentication, HTTPS/TLS, AWS security groups, WAF or application authorization controls, logging, and additional LoadBalancer and data-transfer costs.

## 18B. End-to-End Test Verification Evidence

### 1. Swagger UI Availability

```bash
curl -I http://a15cceb66e8324548bab98dce3caa0f8-1354676405.ap-south-1.elb.amazonaws.com/swagger/index.html
```

Output:
```text
HTTP/1.1 200 OK
Content-Length: 735
Content-Type: text/html;charset=utf-8
Server: Kestrel
```

### 2. Document Upload via API

```bash
echo "%PDF-1.4 test document content for AWS EKS deployment" > /tmp/test-document.pdf
curl -s -X POST -F "file=@/tmp/test-document.pdf;type=application/pdf" \
  http://a15cceb66e8324548bab98dce3caa0f8-1354676405.ap-south-1.elb.amazonaws.com/api/files/upload | jq .
```

Output:
```json
{
  "id": "bac0f8d0-e667-4f26-995e-bf61a3eb73bb",
  "fileName": "test-document.pdf",
  "s3BucketName": "dotnet-app-dev-artifacts",
  "s3ObjectKey": "training-uploads/bac0f8d0e6674f26995ebf61a3eb73bb.pdf",
  "contentType": "application/pdf",
  "fileSize": 54,
  "uploadedAt": "2026-11-18T19:59:55.4774256Z",
  "bucket": "dotnet-app-dev-artifacts",
  "key": "training-uploads/bac0f8d0e6674f26995ebf61a3eb73bb.pdf",
  "originalFileName": "test-document.pdf",
  "sizeBytes": 54
}
```

### 3. S3 Bucket Verification

```bash
aws s3 ls s3://dotnet-app-dev-artifacts/ --recursive --region ap-south-1
```

Output:
```text
2026-11-19 01:29:57         54 training-uploads/bac0f8d0e6674f26995ebf61a3eb73bb.pdf
```

### 4. PostgreSQL Database Verification

Run from the bastion host session:
```bash
export PGPASSWORD='<SECRET_PASSWORD>'
psql -h dotnet-app-dev-postgres.cjiwkuog0e9g.ap-south-1.rds.amazonaws.com \
  -U appadmin -d appdb \
  -c "SELECT * FROM uploaded_files ORDER BY uploaded_at DESC LIMIT 10;"
```

Output:
```text
                  id                  |     file_name     |      s3_bucket_name      |                     s3_object_key                     |  content_type   | file_size |          uploaded_at          
--------------------------------------+-------------------+--------------------------+-------------------------------------------------------+-----------------+-----------+-------------------------------
 bac0f8d0-e667-4f26-995e-bf61a3eb73bb | test-document.pdf | dotnet-app-dev-artifacts | training-uploads/bac0f8d0e6674f26995ebf61a3eb73bb.pdf | application/pdf |        54 | 2026-11-18 19:59:55.477425+00
(1 row)
```

The database record and the S3 object key match.

### 5. Document Retrieval Verification

```bash
curl -s http://a15cceb66e8324548bab98dce3caa0f8-1354676405.ap-south-1.elb.amazonaws.com/api/files/bac0f8d0-e667-4f26-995e-bf61a3eb73bb
```

Output:
```text
%PDF-1.4 test document content for AWS EKS deployment
```

## 19. Common errors & Troubleshooting Guide

### 1. .NET 8 IRSA STS Dependency: `Assembly AWSSDK.SecurityToken could not be found or loaded`

* **Symptom:** File uploads fail with HTTP 500 or 502 with log:
  ```text
  System.IO.FileNotFoundException: Could not load file or assembly 'AWSSDK.SecurityToken, Version=3.3.0.0...'.
  The system cannot find the file specified.
  ```
* **Root Cause:** When running on AWS EKS with IAM Roles for Service Accounts (IRSA), the AWS SDK detects `AWS_WEB_IDENTITY_TOKEN_FILE` and attempts an `AssumeRoleWithWebIdentity` call via AWS STS. The standalone package `AWSSDK.SecurityToken` is required at runtime to perform this token exchange.
* **Resolution:** Add `AWSSDK.SecurityToken` to `app/dotnet.csproj`:
  ```xml
  <PackageReference Include="AWSSDK.SecurityToken" Version="4.1.0.2" />
  <PropertyGroup>
    <SuppressTfmSupportBuildWarnings>true</SuppressTfmSupportBuildWarnings>
  </PropertyGroup>
  ```

### 2. Kubernetes Strategic Merge Patch Conflict: `valueFrom: Invalid value`

* **Symptom:** `kubectl apply -f k8s/deployment.yaml` in the CI/CD pipeline fails with:
  ```text
  The Deployment "dotnet-app" is invalid: spec.template.spec.containers[0].env[4].valueFrom: Invalid value: "": may not be specified when `value` is not empty
  ```
* **Root Cause:** In earlier iterations, `ConnectionStrings__Rds` was defined with a static `value`. When switching to `valueFrom.secretKeyRef`, Kubernetes' strategic merge patch engine attempted to merge the existing object rather than replace it, leaving both `value` and `valueFrom` defined on the same environment key.
* **Resolution:** In `Jenkinsfile`, clear the existing key before applying the manifest:
  ```bash
  kubectl set env deployment/dotnet-app ConnectionStrings__Rds- >/dev/null 2>&1 || true
  kubectl apply -f k8s/deployment.yaml
  ```

### 3. Terraform State Lock Deadlock: `Error acquiring the state lock`

* **Symptom:** `terraform plan` or `terraform apply` fails with:
  ```text
  Error: Error acquiring the state lock: ConditionalCheckFailedException / PreconditionFailed
  Lock Info: ID: 03ad0254-2ca6-b7ff-1599-23fcab7c0ca4 ...
  ```
* **Root Cause:** A preceding Terraform process was terminated unexpectedly before releasing the remote state lock on S3/DynamoDB.
* **Resolution:** Forcefully unlock the state using the Lock ID reported in the error message:
  ```bash
  terraform force-unlock -force 03ad0254-2ca6-b7ff-1599-23fcab7c0ca4
  ```

### 4. Bastion Host `kubectl` XML Download Error

* **Symptom:** Running `kubectl` on the bastion instance produces:
  ```text
  /usr/local/bin/kubectl: line 1: syntax error near unexpected token '<'
  ```
* **Root Cause:** In the bastion EC2 user data, a dynamic curl of `$(curl -L -s https://dl.k8s.io/release/stable.txt)` failed or returned an AWS S3 `NoSuchKey` XML response due to transient DNS or rate limiting.
* **Resolution:** Download the explicit, pinned Kubernetes release binary via SSM session:
  ```bash
  curl -fL https://dl.k8s.io/release/v1.33.0/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl
  chmod +x /usr/local/bin/kubectl
  ```

### 5. Jenkins shows HTTP 503

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
