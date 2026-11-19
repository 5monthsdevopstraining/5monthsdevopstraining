data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name_prefix  = "${var.project_name}-${var.environment}"
  cluster_name = "${local.name_prefix}-eks"
  account_id   = data.aws_caller_identity.current.account_id
  partition    = data.aws_partition.current.partition

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Globally unique bucket name (account id makes collisions very unlikely).
  document_bucket_name = "${local.name_prefix}-docs-${local.account_id}"

  # SSM parameter that always points at the latest official Amazon Linux 2023 AMI.
  al2023_ami_ssm_parameter = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
