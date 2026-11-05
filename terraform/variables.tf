variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name (lowercase, letters/numbers only)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.project))
    error_message = "project must be 2-12 lowercase letters/numbers, no dashes (dash is the name separator)."
  }
}

variable "environment" {
  description = "Environment"
  type        = string

  validation {
    condition     = contains(["dev", "qa", "stage", "prod"], var.environment)
    error_message = "environment must be one of: dev, qa, stage, prod."
  }
}

variable "owner" {
  description = "Team or person who owns these resources"
  type        = string
}

variable "created_by" {
  description = "Person or pipeline that created these resources"
  type        = string
}

variable "vpc_cidr" {
  description = "Primary CIDR of the VPC"
  type        = string
}

variable "public_subnets" {
  description = "Public subnets: name => { cidr, az }"
  type = map(object({
    cidr = string
    az   = string
  }))
}

variable "private_subnets" {
  description = "Private subnets: name => { cidr, az }"
  type = map(object({
    cidr = string
    az   = string
  }))
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "public_key_path" {
  description = "Path to your SSH public key"
  type        = string
}

variable "my_ip_cidr" {
  description = "Your laptop's public IP for SSH/Jenkins, e.g. 49.37.12.34/32. Leave empty to auto-detect on every apply."
  type        = string
  default     = ""
}

variable "github_hook_cidrs" {
  description = "GitHub webhook source IPv4 ranges (from https://api.github.com/meta -> hooks)"
  type        = list(string)
  default = [
    "192.30.252.0/22",
    "185.199.108.0/22",
    "140.82.112.0/20",
    "143.55.64.0/20",
    "9.234.98.160/28",
    "9.234.98.176/28",
    "9.234.106.48/28",
  ]
}
