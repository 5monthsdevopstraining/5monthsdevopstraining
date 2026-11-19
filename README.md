# .NET 10 API on AWS EKS with Terraform, Jenkins and Docker

This repository deploys the original application in `dotnet/dotnet.csproj`. That application is **.NET 10**. It uploads a file to **Amazon S3** and checks that it can open a connection to **Amazon RDS PostgreSQL**. **Terraform** builds the AWS infrastructure. **Jenkins** (on EC2) builds the Docker image, pushes it to **ECR**, and deploys it to a private **EKS** cluster. An internet-facing **Application Load Balancer** exposes it.

The sample application that used to live in `src/DotNet8Api/` is not part of this deployment.

```
Developer laptop -> GitHub -> Jenkins EC2 -> .NET 10 SDK container + Docker build -> ECR -> EKS
                                                                                      |-> S3 (PutObject uploads)
                                                                                      |-> RDS PostgreSQL 16 (SELECT 1)
                                                                                      '-> Secrets Manager (Jenkins copies the DB password into a Kubernetes Secret)
```

> **COST WARNING:** this creates paid resources (EKS, EC2, NAT Gateway, RDS, ALB ...) that bill hourly, roughly
> $0.35-0.40/hour in total. It is **not free-tier eligible**. Destroy it when you finish: `bash scripts/cleanup.sh`.
> Details: `docs/COST-ESTIMATE.md`.

## Folder structure
```
dotnet8-eks-terraform/
├── dotnet/                    Original .NET 10 application (dotnet.csproj, Program.cs, controllers)
├── terraform/                 VPC, EKS, ECR, RDS, S3, IAM, Jenkins, load balancer controller role
├── docker/                    Multi-stage Dockerfile (.NET 10 SDK -> ASP.NET 10 Alpine) and .dockerignore
├── jenkins/Jenkinsfile        CI/CD pipeline (IAM role, no stored keys)
├── kubernetes/                namespace, service account, configmap, deployment, service, ingress
├── scripts/                   configure-aws.sh, validate-terraform.sh, deploy.sh, cleanup.sh, create-sample-pdf.sh
└── docs/                      ARCHITECTURE, RUNBOOK, AWS-SETUP, TROUBLESHOOTING, COST-ESTIMATE, SECURITY-CHECKLIST
```

`.dockerignore` at the repository root is the file Docker uses. `docker/.dockerignore` is a copy of it.

The directory name and the Terraform prefix `project_name` (`dotnet8-eks`) are unchanged so an existing AWS stack is not renamed. They are not the application's target framework.

## What the application actually does
| Method | Path | Purpose |
|---|---|---|
| GET | `/swagger` and `/swagger/v1/swagger.json` | Swagger UI and the OpenAPI document. Probes and the load balancer use the JSON document because the application has no `/health` route. |
| POST | `/api/files/upload` | Multipart upload, form field `file`. Non-empty, 10 MB maximum. Stores the object under `S3:KeyPrefix` (default `training-uploads`). |
| GET | `/api/database/connection` | Opens `ConnectionStrings:Rds` and runs `SELECT 1`. Returns `connected` or HTTP 503 `not connected`. |

The application does not list, download, or delete S3 objects. It does not create database tables. Local development notes for the application itself are in `dotnet/README.md`.

## Docker build
From the repository root. The context must be the root so `COPY dotnet/dotnet.csproj` works.

```bash
docker build -f docker/Dockerfile -t dotnet-api:local .
```

* Build stage: `mcr.microsoft.com/dotnet/sdk:10.0`
* Runtime stage: `mcr.microsoft.com/dotnet/aspnet:10.0-alpine`
* Published project: `dotnet/dotnet.csproj` (`dotnet.dll`)
* Listens on port **8080** (`ASPNETCORE_HTTP_PORTS`)
* Runs as the image user `app` (UID 1654)

`dotnet/Properties/launchSettings.json` uses port 5265 for `dotnet run` on a workstation. That file is not how the container listens.

## Local build
Requires the .NET 10 SDK. There is no test project for this application.

```bash
dotnet build dotnet/dotnet.csproj -c Release
```

## Jenkins
Script path: `jenkins/Jenkinsfile`.

Stages: Checkout, Restore, Build, Test, Docker Build, Push to ECR, Cluster Setup, Deploy, Wait for Rollout, Verify.

* Restore and Build execute inside `mcr.microsoft.com/dotnet/sdk:10.0`. The Jenkins host does not install a .NET SDK.
* Test prints that no test project exists and continues. It fails if a `tests/*.csproj` appears, instead of guessing.
* Push uses the instance IAM role (`aws ecr get-login-password`). No access keys.
* Deploy writes a Kubernetes Secret from Secrets Manager, then applies the manifests.
* Verify requires every replica to be Ready and the Service to have endpoints.
* On failure, the pipeline runs `kubectl rollout undo` when this build already has a kubeconfig.

The Kubernetes namespace stays `sample-app` and the service account stays `dotnet-api`. Those names are also Terraform variables (`k8s_namespace`, `k8s_service_account`) and the EKS Pod Identity association. Change them in both places together, then apply Terraform before deploying.

## PostgreSQL and S3
Non-secret settings go through `kubernetes/configmap.yaml`:

| Environment variable | Application setting |
|---|---|
| `AWS__Region` | `AWS:Region` (S3 client region; set from the Terraform region) |
| `S3__BucketName` | `S3:BucketName` |
| `S3__KeyPrefix` | `S3:KeyPrefix` (`training-uploads`) |
| `ASPNETCORE_HTTP_PORTS` | Container port 8080 |

The database password is not in that ConfigMap. RDS stores `{"username","password"}` in Secrets Manager. Jenkins builds:

`ConnectionStrings__Rds=Host=...;Port=5432;Database=...;Username=...;Password=...;SSL Mode=Require;Trust Server Certificate=true`

and applies it as the Secret `dotnet-api-connection`. That matches the connection string documented in `dotnet/README.md`. The AWS SDK on the pod uses the Pod Identity role for S3. The role allows `s3:PutObject` on the bucket objects and nothing else.

## Start here
1. **`docs/AWS-SETUP.md`** - install the AWS CLI, create the `dotnet8-dev` profile, permissions.
2. **`docs/RUNBOOK.md`** - the beginner steps, including the upload and database checks for this application.
3. `docs/ARCHITECTURE.md` - how the parts fit together.
4. `docs/SECURITY-CHECKLIST.md`, `docs/COST-ESTIMATE.md`, `docs/TROUBLESHOOTING.md`.

## Exact commands from start to finish (Ubuntu)
```bash
# 0. Prerequisites (RUNBOOK steps 1-2): Terraform, AWS CLI v2, SSM plugin
# 1. AWS profile (RUNBOOK steps 3-4)
bash scripts/configure-aws.sh
export AWS_PROFILE=dotnet8-dev
aws sts get-caller-identity

# 2. Settings
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
nano terraform/terraform.tfvars              # region + exactly two Availability Zones

# 3. Optional local checks (no AWS resources)
bash scripts/validate-terraform.sh

# 4. Infrastructure: init, fmt, validate, plan, cost warning, you type 'yes', apply (15-25 min)
bash scripts/deploy.sh
terraform -chdir=terraform output

# 5. Push the project to YOUR GitHub repository (never commit tfvars, state, or secrets)
git init -b main && git add . && git commit -m "Initial commit"
git remote add origin https://github.com/<you>/<repo>.git && git push -u origin main

# 6. Jenkins through SSM (leave this running), open http://localhost:8080
eval "$(terraform -chdir=terraform output -raw jenkins_ssm_port_forward_command)"
#    Unlock password: eval "$(terraform -chdir=terraform output -raw jenkins_ssm_shell_command)"
#                     sudo cat /var/lib/jenkins/secrets/initialAdminPassword
#    Create a Pipeline job: "Pipeline script from SCM", script path jenkins/Jenkinsfile, then Build.

# 7. Test (ALB address from: kubectl -n sample-app get ingress, run on the Jenkins server)
export ALB=<load-balancer-dns-name>
curl -s -o /dev/null -w "%{http_code}\n" "http://$ALB/swagger/v1/swagger.json"
bash scripts/create-sample-pdf.sh sample.pdf
curl -s -F "file=@sample.pdf" "http://$ALB/api/files/upload"
curl -s "http://$ALB/api/database/connection"
aws s3 ls "s3://$(terraform -chdir=terraform output -raw s3_bucket_name)/training-uploads/" --recursive

# 8. Clean up when you are done
bash scripts/cleanup.sh
```

## Important things to know
* **The EKS API is private.** `kubectl` works only from inside the VPC, so you use the Jenkins server (`setup-kubectl` over SSM). The pipeline does the deploying.
* **The load balancer is created by Kubernetes, not Terraform.** The AWS Load Balancer Controller builds it from `kubernetes/ingress.yaml`. That is why `scripts/cleanup.sh` deletes the Ingress before `terraform destroy`.
* **No secrets in Git.** The DB password is created by RDS in Secrets Manager. Jenkins and the pods use IAM roles. Bucket name and region reach the pods through a ConfigMap.
* **Do not run `terraform apply` or `terraform destroy` unless you intend to change or delete paid infrastructure.** `scripts/deploy.sh` asks you to type `yes`. `scripts/cleanup.sh` asks you to type `destroy`.
* **Kubernetes version:** left unset so AWS uses its current default version. Set `kubernetes_version` only after checking `aws eks describe-cluster-versions`.
* **Namespace/service account names** (`sample-app`, `dotnet-api`) are defaults in Terraform and fixed in `kubernetes/*.yaml`; if you change one, change both.
