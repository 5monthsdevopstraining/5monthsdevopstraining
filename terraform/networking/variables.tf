variable "name_prefix" {
  description = "Naming prefix: <project>-<environment>-<region>"
  type        = string
}

variable "purpose" {
  description = "Purpose part of the VPC name"
  type        = string
  default     = "app"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
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

variable "tags" {
  description = "Extra tags"
  type        = map(string)
  default     = {}
}