provider "aws" {
  region = var.aws_region

  # Named CLI profile (for example "dotnet8-dev"). Leave null to use the
  # normal AWS credential chain (environment variables, SSO, etc.).
  profile = var.aws_profile

  default_tags {
    tags = local.common_tags
  }
}
