variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "AWS CLI profile (eks/scripts/*.sh use the same one). \"\" = default credentials"
  type        = string
  default     = "saranya"
}

variable "project" {
  description = "Project name (used in resource names)"
  type        = string
}

variable "environment" {
  description = "Environment (used in resource names)"
  type        = string
}

variable "owner" {
  description = "Team or person who owns these resources"
  type        = string
}

variable "created_by" {
  description = "Person or pipeline that created these resources"
  type        = string
}

########## Network ##########

variable "vpc_cidr" {
  description = "CIDR of the EKS VPC (split into 2 public + 2 private /20 subnets)"
  type        = string
  default     = "10.20.0.0/16"
}

########## EKS ##########

variable "kubernetes_version" {
  description = "EKS Kubernetes version (keep KUBECTL_VERSION in scripts/deployer.sh within one minor version)"
  type        = string
  default     = "1.37"
}

variable "node_instance_type" {
  description = "Worker node type. Free plan accounts can only launch Free Tier types: c7i-flex.large (2 vCPU, 4 GB, 29 pods) fits; t3.micro/small are too small (4/11 pods)"
  type        = string
  default     = "c7i-flex.large"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

########## Deployer EC2 (builds the image, runs kubectl/helm inside the VPC) ##########

variable "deployer_instance_type" {
  description = "Deployer EC2 type. It runs Jenkins and builds the .NET image, so it needs 4 GB RAM (c7i-flex.large is Free Tier eligible)"
  type        = string
  default     = "c7i-flex.large"
}

variable "admin_cidrs" {
  description = "CIDRs allowed to SSH into the deployer EC2 and open Jenkins (port 8080). [] = only your current public IP (looked up at plan time)"
  type        = list(string)
  default     = []
}

########## Jenkins (CI/CD on the deployer EC2) ##########

variable "github_repo_url" {
  description = "Git repository Jenkins builds (HTTPS clone URL; a public repo needs no credentials)"
  type        = string
  default     = "https://github.com/5monthsdevopstraining/5monthsdevopstraining.git"
}

variable "github_branch" {
  description = "Branch whose pushes are deployed"
  type        = string
  default     = "main"
}

########## RDS ##########

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_engine_version" {
  type    = string
  default = "17"
}

########## Extra cluster admins ##########

variable "console_admin_arns" {
  description = "Extra IAM user/role ARNs that get cluster-admin (e.g. the identity you use in the AWS console, so it can show nodes and pods). The root user is not supported by EKS access entries."
  type        = list(string)
  default     = []
}

variable "sonar_token" {
  type      = string
  sensitive = true
  default   = ""
}