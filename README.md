# .NET on private EKS

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

```sh
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

The Service is an internal load balancer and is not publicly reachable by default. Test it from a client that can route into the VPC. Use an internet-facing load balancer only after explicitly reviewing the security and cost implications.

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

## Jenkins CI/CD pipeline

The Terraform configuration creates an Amazon Linux EC2 Jenkins host in the public subnet and runs Jenkins in Docker. The EC2 instance uses an IAM role, Docker, AWS CLI, and `kubectl`. Its security group allows the private EKS endpoint and Jenkins web port access.

The EC2 role provides ECR push and EKS describe access. Jenkins itself should be configured with no AWS access keys. Create AWS credentials only if Jenkins runs outside EC2.

To grant Jenkins Kubernetes administration in Terraform, add the Jenkins IAM role or user and its worker security group:

```hcl
jenkins_principal_arns = {
  jenkins = "arn:aws:iam::123456789012:role/JenkinsEKSDeployRole"
}

jenkins_security_group_ids = {
  jenkins = "sg-0123456789abcdef0"
}
```

Apply the Terraform changes before running the pipeline. Jenkins must run inside the VPC, through a VPN or Direct Connect, or otherwise have private routing and DNS access to the cluster endpoint.

Create a Jenkins Pipeline job that uses the repository Jenkinsfile. Configure the pipeline parameters for the actual `.csproj` and DLL names if they differ from the defaults. The pipeline:

1. validates the .NET project and required CLIs;
2. authenticates to ECR and builds the Docker image;
3. pushes a unique build-number image tag;
4. updates the `kubeconfig`;
5. applies the Kubernetes manifests and the new image;
6. waits for a successful rollout.

The EC2 setup also loads Jenkins Configuration as Code and creates a `dotnet-eks-cicd` Pipeline job for branch `manoj-eks-jenkins`. For a private GitHub repository, add a Jenkins Username with token credential named `github-credentials`, then update `jenkins/casc.yaml` to reference it. Do not paste the PAT or AWS access keys into Jenkinsfile or Terraform files.
