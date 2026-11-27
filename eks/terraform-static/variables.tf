# Must match eks/terraform/terraform.tfvars (the IP is found by a name built from these)
variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "aws_profile" {
  type    = string
  
}

variable "project" {
  type    = string
  default = "sample"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "owner" {
  type    = string
  
}

variable "created_by" {
  type    = string
  
}
