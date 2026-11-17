# Standalone Terraform project for the private EKS cluster.
# Creates everything it needs (VPC, EKS, ECR, S3, RDS, deployer EC2 with Jenkins) and deploys the app
# over SSH (deploy.tf) - nothing from ../../terraform is used.
# Runs from your laptop (aws_profile = "" uses the default AWS credentials instead of a profile).

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = { # SSH key pair for the deployer EC2
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = { # writes the private key to deployer-key.pem
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    http = { # looks up your public IP and GitHub's webhook IPs
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    random = { # Jenkins admin password
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile == "" ? null : var.aws_profile # "" = default credentials
  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix  = "${var.project}-${var.environment}-${var.aws_region}"
  cluster_name = "${local.name_prefix}-eks-app"
  azs          = slice(data.aws_availability_zones.available.names, 0, 2)

  # Must match eks/k8s/*.yaml
  k8s_namespace       = "sample-app"
  k8s_service_account = "sample-app"

  # Must match LBC_SA in eks/scripts/deploy-app.sh
  lbc_namespace       = "kube-system"
  lbc_service_account = "aws-load-balancer-controller"

  # Folder in the S3 bucket (s3.tf) for files uploaded through the app
  upload_prefix = "uploads"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    CreatedBy   = var.created_by
    ManagedBy   = "Terraform"
    Stack       = "eks"
  }
}
