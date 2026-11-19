############################
# General
############################
variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "Named AWS CLI profile to use (for example dotnet8-dev). Null = default credential chain."
  type        = string
  default     = null
}

variable "project_name" {
  description = "Short prefix for every AWS resource name. The default stays dotnet8-eks so an existing stack is not renamed or replaced. The deployed application is the .NET 10 project dotnet/dotnet.csproj."
  type        = string
  default     = "dotnet8-eks"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.project_name))
    error_message = "project_name must be 3-24 characters: lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, test, ...)."
  type        = string
  default     = "dev"
}

############################
# Networking
############################
variable "availability_zones" {
  description = "Exactly two Availability Zones in the chosen region (for example [\"ap-south-1a\", \"ap-south-1b\"]). Check yours with: aws ec2 describe-availability-zones --region <region>"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Provide exactly two Availability Zones."
  }
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.30.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs of the two public subnets (same order as availability_zones)."
  type        = list(string)
  default     = ["10.30.0.0/24", "10.30.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs of the two private subnets (same order as availability_zones)."
  type        = list(string)
  default     = ["10.30.10.0/24", "10.30.11.0/24"]
}

############################
# EKS
############################
variable "kubernetes_version" {
  description = "EKS Kubernetes version. Null = the default version AWS offers for new clusters (recommended). To list versions: aws eks describe-cluster-versions --region <region>"
  type        = string
  default     = null
}

variable "node_instance_types" {
  description = "Instance types of the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 3
}

variable "node_disk_size_gb" {
  description = "Root EBS volume size of each worker node (GiB)."
  type        = number
  default     = 20
}

variable "eks_log_retention_days" {
  description = "Retention of the EKS control-plane CloudWatch log group."
  type        = number
  default     = 7
}

variable "additional_eks_admin_arns" {
  description = "Optional extra IAM principal ARNs (roles/users) that get cluster-admin through EKS access entries. Note: the cluster API is private, so they must also have network access to the VPC."
  type        = list(string)
  default     = []
}

variable "k8s_namespace" {
  description = "Kubernetes namespace of the application."
  type        = string
  default     = "sample-app"
}

variable "k8s_service_account" {
  description = "Kubernetes service account used by the application pods."
  type        = string
  default     = "dotnet-api"
}

############################
# Jenkins
############################
variable "jenkins_instance_type" {
  description = "Instance type of the Jenkins server."
  type        = string
  default     = "t3.medium"
}

variable "jenkins_root_volume_gb" {
  description = "Root volume size of the Jenkins server (GiB). Docker images need space."
  type        = number
  default     = 30
}

variable "jenkins_ami_id" {
  description = "Optional Amazon Linux 2023 AMI ID. Null = look up the latest official AL2023 AMI from the public AWS SSM parameter."
  type        = string
  default     = null
}

############################
# ECR
############################
variable "ecr_force_delete" {
  description = "Allow terraform destroy to delete the ECR repository even if it contains images (dev convenience)."
  type        = bool
  default     = true
}

variable "ecr_keep_image_count" {
  description = "How many images the lifecycle policy keeps."
  type        = number
  default     = 20
}

############################
# S3
############################
variable "s3_force_destroy" {
  description = "Allow terraform destroy to empty the (versioned) document bucket (dev convenience). Set to false for anything important."
  type        = bool
  default     = true
}

variable "s3_noncurrent_version_days" {
  description = "Days after which old object versions are permanently deleted."
  type        = number
  default     = 30
}

############################
# RDS
############################
variable "db_instance_class" {
  description = "RDS instance class (small and cheap for development)."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_engine_version" {
  description = "PostgreSQL version. A major version only (\"16\") lets AWS pick the current default minor version."
  type        = string
  default     = "16"
}

variable "db_allocated_storage_gb" {
  description = "Allocated storage (GiB)."
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Name of the initial database."
  type        = string
  default     = "documentsdb"
}

variable "db_username" {
  description = "Master username. The password is generated and stored by RDS in AWS Secrets Manager; it never appears in this repository."
  type        = string
  default     = "pgadmin"
}

variable "db_backup_retention_days" {
  description = "Days of automated backups to keep."
  type        = number
  default     = 7
}

variable "db_skip_final_snapshot" {
  description = "Skip the final snapshot on destroy (dev convenience)."
  type        = bool
  default     = true
}

variable "db_deletion_protection" {
  description = "Protect the database from deletion."
  type        = bool
  default     = false
}
