# Long-lived resources that must survive "terraform destroy" of eks/terraform:
#   - the deployer's Elastic IP -> the Jenkins URL, the GitHub webhook URL and the SSH address never change
# Apply this once; don't destroy it day to day. eks/terraform finds the IP by its Name tag and
# only attaches it to the deployer EC2 (aws_eip_association), so destroying that stack keeps the IP.
# Cost: a public IPv4 address is $0.005/hour, attached or not (about $0.12/day while the stack is down).

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile == "" ? null : var.aws_profile
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      Owner       = var.owner
      CreatedBy   = var.created_by
      ManagedBy   = "Terraform"
      Stack       = "eks-static"
    }
  }
}

locals {
  name_prefix = "${var.project}-${var.environment}-${var.aws_region}" # same as eks/terraform
}

resource "aws_eip" "deployer" {
  domain = "vpc"
  tags   = { Name = "${local.name_prefix}-eip-eks-deployer" } # eks/terraform looks it up by this tag

  lifecycle {
    prevent_destroy = true # losing it changes the Jenkins/webhook URLs; remove this line to really delete it
  }
}

output "deployer_public_ip" {
  value = aws_eip.deployer.public_ip
}

output "jenkins_url" {
  value = "http://${aws_eip.deployer.public_ip}:8080/"
}
