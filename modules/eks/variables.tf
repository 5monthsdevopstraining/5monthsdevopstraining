variable "cluster_name" { type = string }
variable "kubernetes_version" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }

variable "endpoint_public_access" {
  type    = bool
  default = false
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
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

variable "allowed_security_groups" {
  description = "Map of name => SG id allowed to reach the API server on 443"
  type        = map(string)
  default     = {}
}

variable "admin_principals" {
  description = "Map of name => IAM role/user ARN to grant cluster-admin"
  type        = map(string)
  default     = {}
}

variable "s3_bucket_arn" {
  description = "ARN of the application S3 bucket"
  type        = string
  default     = ""
}