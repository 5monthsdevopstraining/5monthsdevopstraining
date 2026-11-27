# .NET on private EKS

For the complete repeatable implementation process, see [TASK_DOCUMENTATION.md](TASK_DOCUMENTATION.md). For day-to-day operations and incident playbooks, see [RUNBOOK.md](RUNBOOK.md).

This project provisions a VPC, an ECR repository, an SSM-only bastion host, and a private-endpoint EKS cluster. The application is deployed from the `k8s/` manifests behind an internal AWS load balancer.

## Prerequisites

- Terraform 1.5 or later
- AWS CLI credentials with permission to create the resources in the Terraform modules
- Docker and a .NET 8 application in the repository root
- `kubectl` on the bastion or another host with VPC connectivity

## Remote state and locking

Create the S3 state bucket before initializing Terraform. Enable S3 bucket versioning, server-side encryption, and block all public access. S3 native lockfiles are enabled with `use_lockfile = true`.

Copy `backend.hcl.example` to a local file, replace the bucket and table names, and initialize with:

```sh
terraform init -backend-config=backend.hcl
```

Do not commit the backend config if it contains account-specific infrastructure details.

## Validate the target region and EKS version

Check the versions available in the selected region before `terraform apply`:

```sh
aws eks describe-cluster-versions --region ap-south-1 \
  --query 'clusterVersions[].clusterVersion' --output text
```

Set `kubernetes_version` to one of the returned supported versions. The default is only an example and can age out.

## Deploy infrastructure

On a fresh stack, create the S3 module first so `module.s3.bucket_arn` is known for the EKS IRSA count condition, then apply the rest:

```sh
terraform apply -target=module.s3 -auto-approve
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```

The cluster endpoint is private. Use the SSM command from `terraform output` to connect to the bastion, or use another VPN, Direct Connect, or equivalent VPC-connected path. The bastion is in a private subnet and requires working NAT access for package downloads and AWS API access.

## Build and push the .NET image

The included `Dockerfile` uses .NET 8 images. Replace `dotnet-app.csproj` and `dotnet-app.dll` with the actual project file and published assembly name when they differ. The assembly name is the project `<AssemblyName>` value, or the project filename when `<AssemblyName>` is omitted.

```sh
REPO=$(terraform output -raw ecr_repository_url)
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=$(terraform output -raw region 2>/dev/null || printf '%s' ap-south-1)

aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
docker build --build-arg PROJECT_FILE=dotnet-app.csproj \
  --build-arg APP_DLL=dotnet-app.dll -t "$REPO:v1" .
docker push "$REPO:v1"
```

Replace `<ECR_REPO_URL>` in `k8s/deployment.yaml` with the `ecr_repository_url` output before applying the manifests. The deployment listens on port 8080, so the application must bind to that port, for example with `ASPNETCORE_URLS=http://+:8080`.

## Deploy and verify Kubernetes resources

Run these commands from the bastion or another VPC-connected host:

```sh
aws eks update-kubeconfig --name "$(terraform output -raw cluster_name)" --region "$(terraform output -raw region)"
kubectl apply -f k8s/
kubectl get nodes
kubectl get pods -l app=dotnet-app
kubectl get svc dotnet-app
```

The Service is currently configured as an internet-facing LoadBalancer for direct public access. Before production use, review authentication, TLS/HTTPS, security controls, WAF protections, and AWS costs.

### Access the application with the AWS LoadBalancer DNS

After the Service is created, retrieve the DNS name:

```bash
kubectl get service dotnet-app
```

Use the `EXTERNAL-IP` or AWS LoadBalancer hostname in the browser or with `curl`:

```bash
curl http://<LOAD_BALANCER_DNS>
```

The manifest uses the internet-facing AWS LoadBalancer scheme. The DNS is reachable directly from the public internet.

To return to a private LoadBalancer, change the Service annotation to:

```yaml
service.beta.kubernetes.io/aws-load-balancer-scheme: internal
```

Do this only after reviewing public exposure, authentication, TLS/HTTPS, security groups, WAF controls, and AWS costs. This project does not enable public LoadBalancer access by default.

## Cost and cleanup

EKS control plane, EC2 nodes, NAT gateways, ECR storage and scans, load balancers, public IPv4 addresses, and data transfer can incur charges. The development default uses `t3.micro`, but Free Tier eligibility depends on the account and region; verify it before deployment. A single NAT gateway is selected by default to reduce development cost, while `single_nat_gateway = false` provides one NAT gateway per AZ for higher availability.

Destroy development resources when finished:

```sh
terraform destroy
```

Before destroying, remove Kubernetes load balancers if needed and confirm that the ECR repository does not contain images you need to retain. Never run `terraform destroy` against a shared or production state without review.

## RDS and S3

Terraform creates a private PostgreSQL RDS instance, a private database subnet group, a VPC security group allowing PostgreSQL only inside the VPC, and an encrypted private S3 bucket with versioning.

The generated RDS password is stored in AWS Secrets Manager. Read the credential JSON with:

```sh
aws secretsmanager get-secret-value \
  --secret-id "$(terraform output -raw rds_secret_arn)" \
  --query SecretString --output text
```

Use `terraform output -raw rds_endpoint` for the database hostname and `terraform output -raw s3_bucket_name` for the artifact bucket name. Keep RDS and the Jenkins EC2 instance private/public exposure as appropriate for the environment.

## Jenkins CI/CD & DevSecOps pipeline (SonarQube + Trivy)

The Terraform configuration creates an Amazon Linux 2023 EC2 host in the public subnet (`4 GB` swap, `vm.max_map_count=262144`) running both **Jenkins** (port `8080`) and **SonarQube 9.9 LTS Community** (port `9000`) on a shared `ci-net` Docker bridge network. The Jenkins container (`Dockerfile.jenkins`) includes **Trivy** (`v0.76.2`), static **Docker CLI**, AWS CLI v2, and `kubectl`.

The EC2 role provides ECR push, EKS describe, and Secrets Manager read access. Jenkins uses no static AWS access keys.

The `Jenkinsfile` automates the full DevSecOps pipeline for branch `manoj-eks-jenkins`:

1. **Validate:** Verifies `app/dotnet.csproj`, `aws`, `docker`, `kubectl`, and `trivy`.
2. **Trivy FS Scan:** Scans source code, NuGet dependencies, secrets, and Kubernetes manifests (`trivy-fs-report.txt` archived).
3. **SonarQube Analysis:** Runs `dotnet-sonarscanner` inside `mcr.microsoft.com/dotnet/sdk:8.0` on `ci-net` and publishes SAST results to `http://sonarqube:9000`.
4. **Build Image:** Builds the .NET 8 multi-stage Docker image (`build-${BUILD_NUMBER}-${GIT_COMMIT_SHORT}`).
5. **Trivy Image Scan:** Scans the built image for `HIGH`/`CRITICAL` CVEs (`trivy-image-report.txt` archived).
6. **Push to ECR:** Authenticates to ECR via IAM and pushes the scanned image.
7. **Deploy to EKS:** Fetches RDS credentials from AWS Secrets Manager into Kubernetes Secret `dotnet-app-db`, substitutes the ECR image URI into `k8s/deployment.yaml` (`maxSurge: 0, maxUnavailable: 1` for `t3.micro` capacity), applies `k8s/serviceaccount.yaml` (IRSA), `k8s/service.yaml`, and `k8s/deployment.yaml`, and verifies rollout.

The EC2 setup also loads Jenkins Configuration as Code and creates a `dotnet-eks-cicd` Pipeline job for branch `manoj-eks-jenkins`. For a private GitHub repository, add a Jenkins Username with token credential named `github-credentials`, then update `jenkins/casc.yaml` to reference it. Do not paste the PAT or AWS access keys into Jenkinsfile or Terraform files.
