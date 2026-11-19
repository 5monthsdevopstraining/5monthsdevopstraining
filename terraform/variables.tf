variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2"
}

variable "project" {
  description = "Project name used in resource names"
  type        = string
  default     = "sample"
}

variable "environment" {
  description = "Environment name used in resource names"
  type        = string
  default     = "dev"
}

variable "sequence" {
  description = "Two-digit sequence number used in resource names"
  type        = string
  default     = "01"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (one per AZ)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (one per AZ)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH to the bastion"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs allowed to SSH to the bastion, e.g. [\"203.0.113.10/32\"]"
  type        = list(string)
}

variable "bastion_instance_type" {
  type    = string
  default = "t3.small"
}

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "node_instance_type" {
  type    = string
  default = "t3.small"
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

variable "app_port" {
  description = "Port your application container listens on"
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "HTTP path the ALB uses to check pod health"
  type        = string
  default     = "/"
}
