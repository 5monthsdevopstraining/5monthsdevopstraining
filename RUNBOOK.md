# Operations Runbook: .NET 8 EKS Microservice & CI/CD Platform

**Environment:** Development (`dev`)  
**AWS Region:** `ap-south-1` (Asia Pacific - Mumbai)  
**Cluster:** `dotnet-app-dev-eks` (Kubernetes v1.33)  
**Last Updated:** November 2026  

---

## 1. Quick Reference & Core Infrastructure

| Component | Identifier / Resource | Connection / URL |
| :--- | :--- | :--- |
| **Public LoadBalancer** | AWS Classic / NLB DNS | `http://a15cceb66e8324548bab98dce3caa0f8-1354676405.ap-south-1.elb.amazonaws.com` |
| **API Swagger UI** | OpenAPI 3.0 Documentation | `http://<LOAD_BALANCER_DNS>/swagger/index.html` |
| **Jenkins CI/CD** | `i-00dfaf15f8f10664a` | `http://13.235.134.118:8080/` |
| **Bastion Host** | `i-0ab35eb0f90ce1776` | Private IP: `10.0.10.143` (Access via AWS SSM) |
| **PostgreSQL RDS** | `dotnet-app-dev-postgres` | `dotnet-app-dev-postgres.cjiwkuog0e9g.ap-south-1.rds.amazonaws.com:5432` |
| **S3 Artifact Bucket** | Private S3 Storage | `s3://dotnet-app-dev-artifacts` (Key prefix: `training-uploads/`) |
| **ECR Registry** | Container Image Repo | `123806349463.dkr.ecr.ap-south-1.amazonaws.com/dotnet-app-dev/dotnet-app` |
| **Secrets Manager** | Database Credentials | `dotnet-app-dev-postgres-credentials` |
| **IRSA IAM Role** | S3 Access IAM Role | `arn:aws:iam::123806349463:role/dotnet-app-dev-eks-app-s3` |

---

## 2. Access & Authentication Procedures

### 2.1. Accessing the Bastion Host
The Bastion host sits inside the private subnet and has direct network routes to the private EKS control plane and RDS PostgreSQL instance.
Connect securely without SSH keys using AWS Systems Manager (SSM):

```bash
aws ssm start-session \
  --target i-0ab35eb0f90ce1776 \
  --region ap-south-1
```

Once connected, switch to root or set the kubeconfig path:
```bash
sudo -i
export KUBECONFIG=/root/.kube/config
```

### 2.2. Accessing the EKS Cluster (`kubectl`)
From your local workstation or the Bastion host:

```bash
aws eks update-kubeconfig \
  --name dotnet-app-dev-eks \
  --region ap-south-1
```

Verify cluster connectivity:
```bash
kubectl get nodes -o wide
kubectl get pods -n default -l app=dotnet-app
```

### 2.3. Connecting to the PostgreSQL RDS Database
From the Bastion host (has `psql` installed and security group authorization on port 5432):

```bash
# 1. Fetch credentials dynamically from AWS Secrets Manager
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id dotnet-app-dev-postgres-credentials \
  --region ap-south-1 \
  --query SecretString --output text)

DB_HOST=$(echo "$SECRET_JSON" | jq -r .host)
DB_USER=$(echo "$SECRET_JSON" | jq -r .username)
DB_PASS=$(echo "$SECRET_JSON" | jq -r .password)
DB_NAME=$(echo "$SECRET_JSON" | jq -r .dbname)

# 2. Connect via psql
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -p 5432
```

Query file upload records:
```sql
SELECT id, file_name, file_size, content_type, uploaded_at FROM uploaded_files ORDER BY uploaded_at DESC LIMIT 5;
```

---

## 3. Deployment & CI/CD Operations

### 3.1. Standard Release via Jenkins
1. Open Jenkins: `http://13.235.134.118:8080/job/dotnet-eks-cicd/`.
2. Click **Build with Parameters** (or **Build Now**).
3. Pipeline will automatically execute:
   * **Validate:** Check `aws`, `docker`, and `kubectl` binaries.
   * **Build and Push:** Compile .NET 8 Release container, tag with `build-<ID>-<COMMIT>`, and push to Amazon ECR.
   * **Deploy to EKS:** Fetch RDS credentials from Secrets Manager, update K8s Secret `dotnet-app-db`, apply manifests, and rollout new image.

### 3.2. Rolling Back a Deployment
If an unhealthy build is deployed, initiate an immediate zero-downtime rollback:

#### Method A: Instant Rollback to Previous Release (CLI)
```bash
# Undo rollout to previous deployment revision
kubectl rollout undo deployment/dotnet-app

# Monitor rollout status
kubectl rollout status deployment/dotnet-app --timeout=3m
```

#### Method B: Pinning a Specific Image Tag
```bash
# Identify previous stable tag from ECR:
aws ecr describe-images \
  --repository-name dotnet-app-dev/dotnet-app \
  --region ap-south-1 \
  --query 'imageDetails[*].imageTags' --output text

# Roll out specific known-good image:
kubectl set image deployment/dotnet-app \
  dotnet-app=123806349463.dkr.ecr.ap-south-1.amazonaws.com/dotnet-app-dev/dotnet-app:build-9-d5a739ad326e
```

---

## 4. Routine Health Checks & Verification

### 4.1. Synthetic Verification Workflow
Execute this 4-step script to verify all layers (Ingress -> Pod -> S3 -> RDS):

```bash
LB_URL="http://a15cceb66e8324548bab98dce3caa0f8-1354676405.ap-south-1.elb.amazonaws.com"

# 1. Database Connection Check
curl -s -f "$LB_URL/api/database/connection" | jq .

# 2. File Upload Test
echo "Healthcheck test payload $(date -u)" > /tmp/healthcheck.txt
UPLOAD_RESP=$(curl -s -f -X POST -F "file=@/tmp/healthcheck.txt;type=text/plain" "$LB_URL/api/files/upload")
echo "$UPLOAD_RESP" | jq .

FILE_ID=$(echo "$UPLOAD_RESP" | jq -r .id)
S3_KEY=$(echo "$UPLOAD_RESP" | jq -r .s3ObjectKey)

# 3. S3 Object Existence Check
aws s3 ls "s3://dotnet-app-dev-artifacts/$S3_KEY" --region ap-south-1

# 4. File Download Verification
DOWNLOAD_CONTENT=$(curl -s -f "$LB_URL/api/files/$FILE_ID")
echo "Downloaded payload: $DOWNLOAD_CONTENT"
```

### 4.2. Workload & Log Inspection
```bash
# Pod status and resource consumption
kubectl get pods -o wide
kubectl top pods -l app=dotnet-app

# Stream live application logs across all replicas
kubectl logs -f -l app=dotnet-app --tail=100 --max-log-requests=10

# Inspect pod lifecycle events
kubectl describe deployment dotnet-app
```

---

## 5. Incident Response & Troubleshooting Playbooks

### Playbook 1: Pods in `CrashLoopBackOff` or `Pending`
* **Symptoms:** Pods restarting continuously or stuck in `Pending`.
* **Diagnosis Steps:**
  ```bash
  # Check failure reason:
  kubectl describe pod <pod-name>
  kubectl logs <pod-name> --previous
  ```
* **Common Root Causes & Fixes:**
  1. *Insufficient Node CPU/Memory:* Check node capacity with `kubectl describe nodes | grep -A 8 "Allocated resources"`. If saturated, scale down other test workloads or increase `node_desired_size` in Terraform.
  2. *Missing Secret:* If pod fails mounting `dotnet-app-db`, verify that the secret exists:
     ```bash
     kubectl get secret dotnet-app-db -o yaml
     ```
     If missing, re-run Jenkins Deploy stage or create it from Secrets Manager.

---

### Playbook 2: S3 Uploads Fail (`HTTP 500` / `502` / `AccessDenied`)
* **Symptoms:** `POST /api/files/upload` fails; logs indicate AWS authentication error.
* **Diagnosis Steps:**
  ```bash
  # Inspect environment variables injected by EKS Webhook
  kubectl exec -it deployment/dotnet-app -- env | grep AWS
  ```
  *Expected variables:*
  * `AWS_ROLE_ARN=arn:aws:iam::123806349463:role/dotnet-app-dev-eks-app-s3`
  * `AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token`
* **Common Root Causes & Fixes:**
  1. *Missing `AWSSDK.SecurityToken` NuGet:* Ensure the .NET project references `AWSSDK.SecurityToken` (v4.1.0.2). Without it, the SDK cannot perform STS token exchange.
  2. *ServiceAccount Misconfiguration:* Verify the pod uses `serviceAccountName: dotnet-app` and that `k8s/serviceaccount.yaml` contains annotation `eks.amazonaws.com/role-arn: arn:aws:iam::123806349463:role/dotnet-app-dev-eks-app-s3`.
  3. *OIDC Trust Policy Mismatch:* Ensure the IAM role trust policy matches the EKS OIDC provider URL and sub `system:serviceaccount:default:dotnet-app`.

---

### Playbook 3: PostgreSQL Database Connection Refusal / Timeout
* **Symptoms:** `GET /api/database/connection` returns 500 or timeout.
* **Diagnosis Steps:**
  1. *Check RDS Instance Status:*
     ```bash
     aws rds describe-db-instances \
       --db-instance-identifier dotnet-app-dev-postgres \
       --region ap-south-1 \
       --query 'DBInstances[0].DBInstanceStatus' --output text
     ```
     Status must be `available`.
  2. *Check Security Group Rules:* Verify that the RDS Security Group allows TCP port 5432 ingress from the EKS Node Security Group.
  3. *Verify Password Synchronization:* If the RDS password was rotated in AWS Secrets Manager, restart the pods to consume the updated secret:
     ```bash
     kubectl rollout restart deployment/dotnet-app
     ```

---

### Playbook 4: Jenkins Pipeline Fails on `kubectl apply`
* **Symptoms:** Jenkins build fails in Stage 3 with:
  `spec.template.spec.containers[0].env[4].valueFrom: Invalid value: "": may not be specified when value is not empty`.
* **Root Cause:** Kubernetes strategic merge patch conflict when transitioning an environment variable from plaintext `value` to `valueFrom.secretKeyRef`.
* **Fix:** The pipeline handles this automatically by running:
  ```bash
  kubectl set env deployment/dotnet-app ConnectionStrings__Rds- >/dev/null 2>&1 || true
  kubectl apply -f k8s/deployment.yaml
  ```

---

### Playbook 5: Jenkins EC2 Host Out of Memory (OOM) / Unresponsive
* **Symptoms:** Jenkins web UI returns HTTP 503 or drops connections.
* **Diagnosis & Recovery:**
  1. Connect to Jenkins via SSM:
     ```bash
     aws ssm start-session --target i-00dfaf15f8f10664a --region ap-south-1
     ```
  2. Check memory & disk:
     ```bash
     free -m
     df -h
     docker ps
     ```
  3. Reclaim disk space and restart container if stopped:
     ```bash
     docker system prune -af --volumes
     docker restart jenkins
     ```

---

## 6. Scaling & Maintenance Operations

### 6.1. Horizontal Pod Autoscaling / Manual Scaling
Scale the application deployment up or down:
```bash
# Scale to 4 replicas
kubectl scale deployment/dotnet-app --replicas=4

# Verify scaling
kubectl get deployment dotnet-app
kubectl get pods -l app=dotnet-app
```

### 6.2. Rotating Database Credentials Safely
To rotate the PostgreSQL credentials with zero downtime:
1. Update the password in Amazon RDS:
   ```bash
   aws rds modify-db-instance \
     --db-instance-identifier dotnet-app-dev-postgres \
     --master-user-password "<NEW_SECURE_PASSWORD>" \
     --apply-immediately \
     --region ap-south-1
   ```
2. Update the secret in AWS Secrets Manager:
   ```bash
   aws secretsmanager update-secret \
     --secret-id dotnet-app-dev-postgres-credentials \
     --secret-string '{"host":"dotnet-app-dev-postgres.cjiwkuog0e9g.ap-south-1.rds.amazonaws.com","port":5432,"dbname":"appdb","username":"appadmin","password":"<NEW_SECURE_PASSWORD>"}' \
     --region ap-south-1
   ```
3. Trigger Jenkins Build to re-fetch the secret and update the Kubernetes Secret, or manually update `dotnet-app-db`:
   ```bash
   kubectl create secret generic dotnet-app-db \
     --from-literal=ConnectionStrings__Rds="Host=dotnet-app-dev-postgres.cjiwkuog0e9g.ap-south-1.rds.amazonaws.com;Port=5432;Database=appdb;Username=appadmin;Password=<NEW_SECURE_PASSWORD>;Ssl Mode=Prefer;" \
     --dry-run=client -o yaml | kubectl apply -f -
   
   # Restart deployment to pick up the new secret
   kubectl rollout restart deployment/dotnet-app
   ```

---

## 7. Emergency Contacts & Escalation

* **EKS Cluster:** `dotnet-app-dev-eks` (AWS Account: `123806349463`)
* **Primary Region:** `ap-south-1`
* **Source Repository:** `https://github.com/5monthsdevopstraining/5monthsdevopstraining.git` (Branch: `manoj-eks-jenkins`)
