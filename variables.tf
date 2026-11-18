variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "dotnet-app"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/24", "10.0.1.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least two public subnet CIDRs are required."
  }
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.11.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least two private subnet CIDRs are required."
  }
}

variable "single_nat_gateway" {
  description = "true = one NAT (cheap, dev). false = one NAT per AZ (HA, prod)."
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  type    = string
  default = "1.33"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must use the EKS minor version format, for example 1.33. Verify that the version is currently supported in the target region before deployment."
  }
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.micro"]
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

variable "jenkins_principal_arns" {
  description = "Map of Jenkins identity names to IAM role/user ARN values granted AmazonEKSClusterAdminPolicy"
  type        = map(string)
  default     = {}
}

variable "jenkins_security_group_ids" {
  description = "Map of Jenkins worker names to security group IDs allowed to reach the private EKS API endpoint"
  type        = map(string)
  default     = {}
}

variable "jenkins_allowed_cidr_blocks" {
  description = "Public CIDR blocks allowed to reach the Jenkins UI"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}