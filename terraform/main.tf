locals {
  # <project>-<environment>-<region>   (modules add -<resource>-<purpose>)
  name_prefix = "${var.project}-${var.environment}-${var.aws_region}"

  # Your current public IP, detected on every plan/apply unless my_ip_cidr is set
  my_ip_cidr = var.my_ip_cidr != "" ? var.my_ip_cidr : "${chomp(data.http.my_ip.response_body)}/32"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    CreatedBy   = var.created_by
    ManagedBy   = "Terraform"
  }
}

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

module "vpc" {
  source = "./networking"

  name_prefix     = local.name_prefix
  purpose         = "app"
  vpc_cidr        = var.vpc_cidr
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
}

resource "aws_key_pair" "ec2" {
  key_name   = "${local.name_prefix}-key-ec2"
  public_key = file(pathexpand(var.public_key_path))

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

module "public_ec2" {
  source = "./instance"

  name_prefix         = local.name_prefix
  purpose             = "publicapp"
  vpc_id              = module.vpc.vpc_id
  subnet_id           = module.vpc.public_subnet_ids["public1"]
  private_ip          = "10.0.1.10" # fixed: used as PUBLIC_HOST in the Jenkinsfile
  instance_type       = var.instance_type
  key_name            = aws_key_pair.ec2.key_name
  associate_public_ip = true

  ingress_rules = {
    http = {
      description = "App (HTTP) from internet"
      port        = 80
      cidr_ipv4   = "0.0.0.0/0"
    }
    ssh = {
      description = "SSH from my laptop only"
      port        = 22
      cidr_ipv4   = local.my_ip_cidr
    }
    ssh_from_jenkins = {
      description              = "SSH from Jenkins (deployments)"
      port                     = 22
      source_security_group_id = module.public_ec2_2.security_group_id
    }
  }

  depends_on = [module.vpc]
}

module "public_ec2_2" {
  source = "./instance"

  name_prefix         = local.name_prefix
  purpose             = "jenkins"
  vpc_id              = module.vpc.vpc_id
  subnet_id           = module.vpc.public_subnet_ids["public2"]
  instance_type       = "t3.small" # Jenkins needs ~2 GB RAM; t3.micro (1 GB) is too small
  root_volume_size    = 20
  key_name            = aws_key_pair.ec2.key_name
  associate_public_ip = true

  user_data = file("${path.module}/instance/scripts/jenkins.sh")

  ingress_rules = merge(
    {
      jenkins = {
        description = "Jenkins UI from my laptop only"
        port        = 8080
        cidr_ipv4   = local.my_ip_cidr
      }
      ssh = {
        description = "SSH from my laptop only"
        port        = 22
        cidr_ipv4   = local.my_ip_cidr
      }
    },
    {
      for i, cidr in var.github_hook_cidrs : "github_hook_${i}" => {
        description = "GitHub webhooks to Jenkins"
        port        = 8080
        cidr_ipv4   = cidr
      }
    }
  )

  depends_on = [module.vpc]
}

# Fixed public IP for Jenkins, so its URL and the GitHub webhook survive stop/start
resource "aws_eip" "jenkins" {
  instance = module.public_ec2_2.instance_id
  domain   = "vpc"

  tags = {
    Name = "${local.name_prefix}-eip-jenkins"
  }
}

module "private_ec2" {
  source = "./instance"

  name_prefix         = local.name_prefix
  purpose             = "privateapp"
  vpc_id              = module.vpc.vpc_id
  subnet_id           = module.vpc.private_subnet_ids["private1"]
  private_ip          = "10.0.3.10" # fixed: used as PRIVATE_HOST in the Jenkinsfile
  instance_type       = var.instance_type
  key_name            = aws_key_pair.ec2.key_name
  associate_public_ip = false

  ingress_rules = {
    ssh_from_public = {
      description              = "SSH from public EC2 only (bastion)"
      port                     = 22
      source_security_group_id = module.public_ec2.security_group_id
    }
    ssh_from_jenkins = {
      description              = "SSH from Jenkins (deployments)"
      port                     = 22
      source_security_group_id = module.public_ec2_2.security_group_id
    }
    app_from_public = {
      description              = "App port from public EC2"
      port                     = 8080
      source_security_group_id = module.public_ec2.security_group_id
    }
    app_from_jenkins = {
      description              = "App port from Jenkins (health check)"
      port                     = 8080
      source_security_group_id = module.public_ec2_2.security_group_id
    }
  }

  depends_on = [module.vpc]
}