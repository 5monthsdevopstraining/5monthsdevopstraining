variable "name_prefix" {
  description = "Naming prefix: <project>-<environment>-<region>"
  type        = string
}

variable "purpose" {
  description = "Purpose part of the name, e.g. publicapp"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the security group"
  type        = string
}

variable "subnet_id" {
  description = "Subnet to launch the instance in"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of the EC2 key pair for SSH"
  type        = string
}

variable "private_ip" {
  description = "Fixed private IP inside the subnet (null = AWS picks one)"
  type        = string
  default     = null
}

variable "iam_instance_profile" {
  description = "IAM instance profile name (null = none)"
  type        = string
  default     = null
}

variable "associate_public_ip" {
  description = "Give the instance a public IP"
  type        = bool
  default     = false
}

variable "user_data" {
  description = "Startup script"
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Root disk size in GB"
  type        = number
  default     = 8
}

variable "ingress_rules" {
  description = "Inbound rules: name => { description, port, cidr_ipv4 OR source_security_group_id }"
  type = map(object({
    description              = string
    port                     = number
    cidr_ipv4                = optional(string)
    source_security_group_id = optional(string)
  }))
  default = {}
}

variable "tags" {
  description = "Extra tags"
  type        = map(string)
  default     = {}
}