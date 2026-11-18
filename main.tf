data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name         = "${var.project}-${var.environment}"
  cluster_name = "${local.name}-eks"
  azs          = slice(data.aws_availability_zones.available.names, 0, length(var.private_subnet_cidrs))

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "terraform_data" "configuration_validation" {
  lifecycle {
    precondition {
      condition     = length(var.public_subnet_cidrs) == length(var.private_subnet_cidrs)
      error_message = "public_subnet_cidrs and private_subnet_cidrs must contain the same number of CIDRs."
    }

    precondition {
      condition     = length(var.private_subnet_cidrs) >= 2
      error_message = "At least two private subnet CIDRs are required for a multi-AZ EKS cluster."
    }
  }
}

module "networking" {
  source = "./modules/networking"

  name                 = local.name
  cluster_name         = local.cluster_name
  vpc_cidr             = var.vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
}

module "ecr" {
  source = "./modules/ecr"

  repository_name = "${local.name}/dotnet-app"
}

module "s3" {
  source = "./modules/s3"

  bucket_name = "${local.name}-artifacts"
  tags        = local.tags
}

module "rds" {
  source = "./modules/rds"

  name                = "${local.name}-postgres"
  vpc_id              = module.networking.vpc_id
  subnet_ids          = module.networking.private_subnet_ids
  allowed_cidr_blocks = [module.networking.vpc_cidr]
  tags                = local.tags
}

module "bastion" {
  source = "./modules/bastion"

  name      = local.name
  vpc_id    = module.networking.vpc_id
  subnet_id = module.networking.private_subnet_ids[0]
}

module "jenkins" {
  source = "./modules/jenkins"

  name                = "${local.name}-jenkins"
  vpc_id              = module.networking.vpc_id
  subnet_id           = module.networking.public_subnet_ids[0]
  allowed_cidr_blocks = var.jenkins_allowed_cidr_blocks
  repository_url      = "https://github.com/5monthsdevopstraining/5monthsdevopstraining.git"
  branch              = "manoj-eks-jenkins"
  tags                = local.tags
}

module "eks" {
  source = "./modules/eks"

  cluster_name           = local.cluster_name
  kubernetes_version     = var.kubernetes_version
  vpc_id                 = module.networking.vpc_id
  subnet_ids             = module.networking.private_subnet_ids
  endpoint_public_access = false
  node_instance_types    = var.node_instance_types
  node_desired_size      = var.node_desired_size
  node_min_size          = var.node_min_size
  node_max_size          = var.node_max_size
  allowed_security_groups = merge(
    { bastion = module.bastion.security_group_id },
    { jenkins = module.jenkins.security_group_id },
    var.jenkins_security_group_ids
  )
  admin_principals = merge(
    { bastion = module.bastion.role_arn },
    { jenkins = module.jenkins.role_arn },
    var.jenkins_principal_arns
  )
}