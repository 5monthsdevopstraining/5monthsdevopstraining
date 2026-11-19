terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 5.70+ is needed for EKS access entries, Pod Identity and the
      # EKS upgrade_policy (standard support) settings used in this project.
      version = ">= 5.70.0, < 6.0.0"
    }
  }
}
