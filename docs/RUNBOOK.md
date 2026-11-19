# RUNBOOK - from zero to the original .NET 10 API on EKS

Ubuntu Bash only. Every command is followed by what it does.
Run all commands from the **repository root** (`dotnet8-eks-terraform/`) unless told otherwise.

> **COST WARNING** - Step 11 creates paid AWS resources (EKS, EC2, NAT Gateway, RDS, ALB ...).
> They bill every hour, even when idle, and this is **not free-tier eligible**. See `docs/COST-ESTIMATE.md`.
> Do step 21 when you finish.

Important to know: the EKS API is **private** (no public endpoint), so `kubectl` does not work from your laptop.
You run `kubectl` on the Jenkins server through AWS Systems Manager (SSM). That is steps 12-13.

---

## Part A - Prepare your Ubuntu machine

### 1. Install Terraform
```bash
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl unzip
```
Updates the package list and installs helper tools.

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
```
Downloads HashiCorp's signing key so Ubuntu can verify the packages.

```bash
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
```
Adds the official HashiCorp package repository.

```bash
sudo apt-get update && sudo apt-get install -y terraform
terraform version
```
Installs Terraform and prints its version (needs 1.6 or newer).

### 2. Install the AWS CLI v2 (and the SSM plugin)
```bash
bash scripts/configure-aws.sh
```
Installs the AWS CLI if missing and walks you through step 3. If you prefer to do it by hand:

```bash
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp && sudo /tmp/aws/install
aws --version
```
Downloads, unpacks and installs the AWS CLI, then prints its version.

The SSM plugin lets your laptop open sessions to Jenkins (Ubuntu 64-bit x86; for ARM see the AWS docs):
```bash
curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o /tmp/ssm-plugin.deb
sudo dpkg -i /tmp/ssm-plugin.deb
session-manager-plugin --version
```
Downloads and installs the plugin, then checks it works.

### 3. Configure your AWS account (named profile `dotnet8-dev`)
Read `docs/AWS-SETUP.md` first. The short version:
```bash
aws configure --profile dotnet8-dev
```
Asks for access key, secret key, default region and output format and stores them in `~/.aws/` on your machine only.
**Prefer** `aws configure sso --profile dotnet8-dev` if your company uses IAM Identity Center (short-lived credentials).
Never paste these values into chats, tickets or Git.

```bash
export AWS_PROFILE=dotnet8-dev
```
Makes every following `aws` and `terraform` command in this terminal use that profile.

### 4. Verify your AWS identity
```bash
aws sts get-caller-identity
```
Prints the account ID and IAM identity you are using. If this fails, stop and fix it (see `docs/AWS-SETUP.md`).

---

## Part B - Build the infrastructure

### 5. Configure `terraform.tfvars`
```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```
Copies the example settings. `terraform.tfvars` is ignored by Git.

```bash
aws ec2 describe-availability-zones --region ap-south-1 --query 'AvailabilityZones[].ZoneName' --output text
nano terraform/terraform.tfvars
```
Lists the real Availability Zones in your region, then opens the file so you can set `aws_region` and `availability_zones` (exactly two) to match.

### 6. Initialize Terraform
```bash
cd terraform
terraform init
```
Downloads the AWS provider and prepares the working folder. It creates **no** AWS resources.

### 7. Format the Terraform files
```bash
terraform fmt -recursive
```
Rewrites the files into the standard Terraform style.

### 8. Validate Terraform
```bash
terraform validate
```
Checks syntax and references between resources. It does not contact AWS.

### 9. Generate the Terraform plan
```bash
terraform plan -out=tfplan
```
Asks AWS what exists and writes a plan of what *would* be created into the file `tfplan`. Nothing is created yet.

### 10. Review the plan
Read the output. Check that:
* every resource name starts with `dotnet8-eks-dev`;
* the summary says `Plan: N to add, 0 to change, 0 to destroy`;
* nothing says "destroy" or "replace" for resources you care about.

### 11. Apply Terraform (creates paid resources)
```bash
terraform apply tfplan
```
Creates everything in the plan. It takes **15-25 minutes** (EKS and RDS are slow). It only applies the exact plan you reviewed.

```bash
terraform output
cd ..
```
Prints the important values (cluster name, bucket, ECR URL, Jenkins instance ID). Then returns to the repo root.

Wait about 5 more minutes: the Jenkins server installs software on first boot. That install includes Java, Git, Docker, kubectl, Helm, and Jenkins. It does not install a .NET SDK. The pipeline uses the .NET 10 SDK container.

If you already applied an older version of this project, the Jenkins user-data change replaces the Jenkins EC2 instance (`user_data_replace_on_change` is true). Back up `/var/lib/jenkins` first if you need the existing jobs. A new environment is not affected.

---

## Part C - Reach the cluster and Jenkins

### 12. Configure kubectl (on the Jenkins server)
```bash
eval "$(terraform -chdir=terraform output -raw jenkins_ssm_shell_command)"
```
Opens a shell on the Jenkins server through SSM (no SSH, no public IP). You are now **on the server**. Run:

```bash
sudo tail -n 5 /var/log/jenkins-bootstrap.log
```
Should end with `Jenkins bootstrap finished`. If not, wait a minute and repeat.

```bash
setup-kubectl
```
A helper installed on the Jenkins server. It reads the (non-secret) cluster settings from `/etc/platform.env`, runs
`aws eks update-kubeconfig` (writes the cluster connection into `~/.kube/config`) and then `kubectl get nodes`.

### 13. Verify the EKS nodes
Still in the SSM session:
```bash
kubectl get nodes
```
Shows the worker nodes; they should be `Ready`.
```bash
kubectl get pods -n kube-system
```
Shows system pods (CoreDNS, kube-proxy, aws-node, eks-pod-identity-agent), which should be `Running`.

Type `exit` to leave the session.

### 14. Open Jenkins through SSM port forwarding
```bash
eval "$(terraform -chdir=terraform output -raw jenkins_ssm_port_forward_command)"
```
Opens a secure tunnel: Jenkins on the server (port 8080) appears at `http://localhost:8080` on your laptop. Leave this terminal open.

In a **second terminal**:
```bash
eval "$(terraform -chdir=terraform output -raw jenkins_ssm_shell_command)"
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
exit
```
Shows the one-time unlock password.

In your browser open `http://localhost:8080`, paste the password, choose **Install suggested plugins**, and create your admin user.

---

## Part D - Build and deploy the app

### 15. Run the Jenkins pipeline
1. Put the project in your own GitHub repository (from the repo root):
   ```bash
   git init -b main
   git add .
   git status
   git commit -m "Initial commit"
   git remote add origin https://github.com/<you>/<repo>.git
   git push -u origin main
   ```
   `git status` lets you confirm that `terraform.tfvars` and `*.tfstate` are **not** listed.
2. Private repository? In Jenkins: *Manage Jenkins -> Credentials -> Global -> Add Credentials ->
   Username with password* (your GitHub user name and a **fine-grained personal access token** with read-only
   access to this repo). Jenkins stores it encrypted; it is never written into a file in Git.
3. In Jenkins: *New Item -> Pipeline*. Under *Pipeline* choose **Pipeline script from SCM**, SCM **Git**,
   your repository URL (and the credentials), branch `*/main`, script path `jenkins/Jenkinsfile`. Save.
4. Click **Build with Parameters -> Build**. The first run installs the AWS Load Balancer Controller and takes ~10 minutes.

The stages are: Checkout, Restore, Build, Test, Docker Build, Push to ECR, Cluster Setup, Deploy, Wait for Rollout, Verify.

Restore and Build run inside `mcr.microsoft.com/dotnet/sdk:10.0`. The Jenkins EC2 instance does not install a .NET SDK. The Test stage finds no test project for `dotnet/dotnet.csproj`, says so, and continues. It does not run tests from the removed sample application. Deploy reads the RDS username and password from Secrets Manager and stores `ConnectionStrings__Rds` in the Kubernetes Secret `dotnet-api-connection`.

### 16. Verify the application deployment
Back in an SSM shell on the Jenkins server (step 12 command):
```bash
kubectl -n sample-app get pods,svc,ingress
```
Shows 2 `Running` pods, the `ClusterIP` service and the Ingress. The ALB address appears under `ADDRESS` after 2-4 minutes.
```bash
kubectl -n sample-app logs deploy/dotnet-api --tail=20
```
Shows the application logs (look for Kestrel listening on port 8080). This application does not log "Database is ready."

Save the address:
```bash
ALB=$(kubectl -n sample-app get ingress dotnet-api -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'); echo "$ALB"
```
Stores the load balancer DNS name in a variable and prints it. On your laptop run `export ALB=<that-name>`.

### 17. Test Swagger
```bash
curl -s -o /dev/null -w "%{http_code}\n" "http://$ALB/swagger/v1/swagger.json"
```
Prints `200` when the API is serving. This application has no `/health` endpoint. Kubernetes and the load balancer use `/swagger/v1/swagger.json` for the same reason.
Open `http://<ALB-address>/swagger` in your browser.

### 18. Upload a file
```bash
bash scripts/create-sample-pdf.sh sample.pdf
```
Creates a tiny file named `sample.pdf`. Any non-empty file up to 10 MB works; the API does not require a PDF.
```bash
curl -s -F "file=@sample.pdf" "http://$ALB/api/files/upload"
```
Uploads it. The reply contains `bucket`, `key`, `originalFileName`, and `sizeBytes`. The API does not return a public URL.

### 19. Verify the file in S3
```bash
aws s3 ls "s3://$(terraform -chdir=terraform output -raw s3_bucket_name)/training-uploads/" --recursive
```
Lists the uploaded object under the `training-uploads/` prefix.

### 20. Verify PostgreSQL
RDS is private. The application only checks connectivity; it does not create tables.
```bash
curl -s "http://$ALB/api/database/connection"
```
A working connection returns `"status":"connected"`. A missing connection string or a network failure returns HTTP 503 and `"status":"not connected"`.

Direct SQL check (optional). On your **laptop** read the generated password (it never goes into Git):
```bash
aws secretsmanager get-secret-value --secret-id "$(terraform -chdir=terraform output -raw db_secret_arn)" --query SecretString --output text
```
Prints `{"username":"...","password":"..."}`. Then in an SSM shell on Jenkins:
```bash
read -rs -p "DB password: " PGPASSWORD; echo
source /etc/platform.env
kubectl -n sample-app run psql-check --rm -it --restart=Never --image=postgres:16-alpine \
  --env="PGPASSWORD=$PGPASSWORD" -- \
  psql "host=$DB_HOST user=pgadmin dbname=documentsdb sslmode=require" \
  -c 'SELECT 1;'
unset PGPASSWORD
```
`read -rs` hides what you type. The temporary pod runs inside the cluster (the only place allowed to reach RDS) and disappears. `SELECT 1` is the same check the API performs.

---

## Part E - Clean up

### 21. Clean up development resources safely
```bash
bash scripts/cleanup.sh
```
Asks you to type `destroy`. Then it (1) deletes the Kubernetes Ingress through Jenkins so the load balancer is removed
(Terraform does not manage it), and (2) runs `terraform destroy`. Afterwards check the AWS console (EC2 load balancers,
EKS, RDS, VPC, Elastic IPs) and **Billing** for anything left.

Things that never get deleted automatically: your local `~/.aws` profile, the GitHub repository, and RDS snapshots if you
turned `db_skip_final_snapshot` off.

---

## All commands in one list (copy/paste order)
```bash
bash scripts/configure-aws.sh && export AWS_PROFILE=dotnet8-dev
cp terraform/terraform.tfvars.example terraform/terraform.tfvars && nano terraform/terraform.tfvars
bash scripts/deploy.sh                      # init + fmt + validate + plan + asks 'yes' + apply
terraform -chdir=terraform output
eval "$(terraform -chdir=terraform output -raw jenkins_ssm_port_forward_command)"   # open http://localhost:8080
# create the Jenkins pipeline job, click Build, then test with curl (steps 16-20)
bash scripts/cleanup.sh
```
