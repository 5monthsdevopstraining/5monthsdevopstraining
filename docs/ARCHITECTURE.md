# Architecture

```
Developer laptop --git push--> GitHub
                                 |
                    (Jenkins pulls the code)
                                 v
  +----------------------------------------------- VPC 10.30.0.0/16 ------------------------------------------------+
  |  PUBLIC subnets (2 AZs)                         PRIVATE subnets (2 AZs)                                         |
  |  - Internet Gateway                             - Jenkins EC2 (no public IP, reached with SSM)                  |
  |  - NAT Gateway  <-- outbound-only internet ---- - EKS worker nodes (managed node group)                         |
  |  - internet-facing ALB  --HTTP--> pod IPs       - .NET 10 API pods --5432--> RDS PostgreSQL 16 (private)        |
  |                                                  - S3 gateway endpoint (free) --> S3 bucket (uploads)           |
  +-----------------------------------------------------------------------------------------------------------------+
  Jenkins --docker push--> Amazon ECR --image pull--> EKS nodes
  Jenkins --reads at deploy time--> Secrets Manager (DB username and password) --> Kubernetes Secret
  .NET pods --Pod Identity role--> S3 PutObject. The process reads ConnectionStrings__Rds from that Secret.
```

## What each part does (simple language)
| Part | Purpose |
|---|---|
| **VPC** | Your own private network in AWS. Everything lives inside it. |
| **Public subnets** | Can talk to the internet directly. Only the load balancer and NAT Gateway live here. |
| **Private subnets** | No direct internet access. Nodes, Jenkins and the database are here. They go out through the NAT Gateway. |
| **NAT Gateway** | Lets private machines download packages/images, but nobody can connect *in* through it. |
| **S3 gateway endpoint** | A private shortcut to S3 so file traffic does not go through (and cost money on) the NAT Gateway. |
| **EKS** | Managed Kubernetes. AWS runs the control plane; you run the worker nodes. The API is **private**. |
| **Managed node group** | The EC2 machines (t3.medium) that run your pods. |
| **ECR** | Private store for Docker images, with vulnerability scanning on push. |
| **Jenkins EC2** | Restores and builds inside the .NET 10 SDK container, pushes the image, and deploys. It has an IAM role instead of passwords/keys. The host does not install a .NET SDK. |
| **SSM Session Manager** | Secure shell and port-forwarding to Jenkins without opening any port or using SSH keys. |
| **AWS Load Balancer Controller** | A pod that watches Ingress objects and creates the real Application Load Balancer. |
| **RDS PostgreSQL 16** | Private PostgreSQL instance. The application only checks that it can connect (`SELECT 1`). It does not create tables. Only the EKS workload security group may connect. |
| **S3 bucket** | Private, encrypted, versioned bucket. The application uploads one object per `POST /api/files/upload`. |
| **Secrets Manager** | Holds the database user/password (created and rotated by RDS). |
| **EKS Pod Identity** | Gives the pods of service account `sample-app/dotnet-api` temporary AWS credentials for **one** IAM role. |

## IAM roles (separate on purpose)
| Role | Trusted by | Can do |
|---|---|---|
| `...-eks-cluster-role` | EKS service | Manage the control plane (AmazonEKSClusterPolicy). |
| `...-eks-node-role` | EC2 | Join the cluster, VPC CNI networking, pull images **from our ECR repo only**. |
| `...-jenkins-role` | EC2 | SSM sessions; push to our ECR repo; `eks:DescribeCluster` on our cluster; `secretsmanager:GetSecretValue` on the RDS secret only. Cluster-admin inside Kubernetes via an EKS access entry (dev trade-off, see the security checklist). |
| `...-app-role` | EKS Pod Identity | `s3:PutObject` on the bucket objects, and read **only** the DB secret. The running application uses the S3 permission. It does not call Secrets Manager. |
| `...-lb-controller-role` | EKS Pod Identity | The official AWS Load Balancer Controller policy. |

## Network and security-group flow
* Internet -> ALB (80) -> pods (8080). The ALB security group is managed by the Load Balancer Controller.
* Pods -> RDS (5432): allowed because the RDS security group accepts the **EKS cluster security group** only.
* Jenkins -> EKS API (443): allowed by `eks-api-access-sg` which accepts the Jenkins security group only.
* Jenkins security group: no inbound rules at all.
* Nobody on the internet can reach RDS, Jenkins, the nodes or the Kubernetes API.

## Request flow: uploading a file
1. `POST /api/files/upload` (multipart field `file`) reaches the ALB, then a pod.
2. The app rejects an empty file and any file larger than 10 MB.
3. The app uploads the bytes to S3 under `S3:KeyPrefix` (default `training-uploads/<guid>.<ext>`).
4. The response contains the bucket, object key, original file name, and size. The object stays private.

The application does not download or delete objects, and it does not write a database row for the file.

## Request flow: checking PostgreSQL
1. `GET /api/database/connection` opens `ConnectionStrings:Rds` and runs `SELECT 1`.
2. A missing connection string or a failed connection returns HTTP 503 with status `not connected`.
3. A successful check returns HTTP 200 with status `connected`.

Jenkins builds that connection string at deploy time from the RDS secret in Secrets Manager plus the host, port, and database name. The password is stored in the Kubernetes Secret `dotnet-api-connection`, not in a ConfigMap and not in Git. A later pipeline run picks up a rotated password and new pods receive it. The application code itself never calls Secrets Manager.

S3 credentials: the AWS SDK uses the default credential chain. On EKS that is the Pod Identity role. No access keys are configured.

## Why the cluster API is private (and what that means for you)
`kubectl` can only reach the cluster from inside the VPC. That is why you run it on the Jenkins server via SSM
(`setup-kubectl`) and why the pipeline, not your laptop, deploys the application.

## Terraform state security
Terraform records everything it created in a **state file**. State can contain sensitive values, so:
* It is **never committed** (`.gitignore` blocks `*.tfstate*` and `terraform.tfvars`).
* This project uses the default **local** state in `terraform/` (new state, your existing state is not touched). Keep that folder private.
* This design avoids putting the database password into state at all (RDS manages it in Secrets Manager).
* For a team or anything important, use a **remote backend**: an S3 bucket with versioning, encryption and blocked public
  access, and state locking. Example (create the bucket yourself first, then add this as `terraform/backend.tf`):
  ```hcl
  terraform {
    backend "s3" {
      bucket       = "<your-private-state-bucket>"
      key          = "dotnet8-eks/dev/terraform.tfstate"
      region       = "ap-south-1"
      encrypt      = true
      use_lockfile = true   # native S3 locking (Terraform 1.10+); older versions use a DynamoDB table
    }
  }
  ```
* Limit who can read the state bucket: whoever reads state can learn resource details.

## Deliberate simplifications (development project)
Single NAT Gateway (one AZ), single-AZ RDS, plain-HTTP ALB, Swagger exposed (the application always turns it on),
Jenkins cluster-admin, TLS to RDS with `Trust Server Certificate=true`. The application does not run database migrations.
See `docs/SECURITY-CHECKLIST.md` for production fixes.
