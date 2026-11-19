# Security

## What this project already does
- [x] No AWS access keys or passwords in code, Terraform, Jenkinsfile, Kubernetes YAML or Docker image.
- [x] Database password generated and stored by RDS in AWS Secrets Manager. Jenkins reads that secret at deploy time and puts `ConnectionStrings__Rds` in a Kubernetes Secret. The value is not in Git or in a ConfigMap.
- [x] RDS not publicly accessible; ingress on 5432 only from the EKS cluster security group.
- [x] EKS API endpoint private only (no public endpoint).
- [x] S3: public access blocked, encryption on, versioning on, HTTPS-only bucket policy, ACLs disabled.
- [x] EC2 IMDSv2 required (Jenkins and worker nodes); pods cannot reach the node metadata service (hop limit 1).
- [x] Encrypted EBS (Jenkins, nodes) and encrypted RDS storage.
- [x] Separate IAM roles for cluster, nodes, Jenkins, application and load balancer controller.
- [x] Jenkins has no public IP and no inbound rules; reached through SSM.
- [x] Container runs as non-root, read-only root filesystem, all Linux capabilities dropped.
- [x] ECR scan on push; immutable image tags.
- [x] `terraform.tfvars`, state files and plans are git-ignored.

## Known development shortcuts - fix before production
- [ ] **ALB is plain HTTP and open to the internet.** Add an ACM certificate, HTTPS listener (443), redirect 80->443, a WAF, and restrict `inbound-cidrs`.
- [ ] **Jenkins is cluster-admin in Kubernetes.** Replace with a narrow access policy scoped to the `sample-app` namespace, and move cluster add-on installation (namespace, Load Balancer Controller) to a separate admin-only pipeline or Terraform.
- [ ] **Single NAT Gateway / single-AZ RDS / one Jenkins.** Use one NAT per AZ, Multi-AZ RDS, and back up Jenkins.
- [ ] **TLS to RDS trusts the server certificate.** Install the RDS CA bundle and use `SslMode=VerifyFull`.
- [ ] **Swagger is public.** `Program.cs` always calls `UseSwagger` and `UseSwaggerUI`. There is no off switch. Put it behind authentication or remove those calls in the application if you need to hide it.
- [ ] **The API has no authentication.** Add OIDC/JWT (for example Amazon Cognito) and authorization.
- [ ] **Egress is open.** Restrict outbound traffic with security groups / network policies and use VPC endpoints (ECR, STS, Secrets Manager, SSM) instead of the NAT Gateway.
- [ ] **EKS secrets are not envelope-encrypted with a customer KMS key.** The database connection string now lives in a Kubernetes Secret, so add `encryption_config` with a CMK before production.
- [ ] **S3 uses SSE-S3.** Consider SSE-KMS with a customer-managed key and bucket access logging.
- [ ] **The application does not manage a schema.** `GET /api/database/connection` only runs `SELECT 1`. Add migrations in the application if you later store data.
- [ ] **Terraform state is local.** Use an encrypted, versioned, locked remote backend with restricted access.
- [ ] **Jenkins hardening:** keep Jenkins and plugins updated, enable authorization, enable audit logging, back up `/var/lib/jenkins`.
- [ ] **Monitoring:** CloudWatch alarms, GuardDuty, CloudTrail, EKS audit-log review.
- [ ] **Pod-to-pod isolation:** add Kubernetes NetworkPolicies, Pod Security Admission (restricted) and consider security groups for pods so only the app pods (not every node) can reach RDS.
- [ ] **Backups and recovery:** RDS Multi-AZ, tested restores, S3 replication if required, deletion protection on RDS.
- [ ] **Image supply chain:** pin base image digests, scan in CI, sign images.
