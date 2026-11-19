locals {
  # <resource>-<project>-<env>-<region>-<nn>  e.g. eks-sample-dev-ap-southeast-2-01
  name_suffix = "${var.project}-${var.environment}-${var.region}-${var.sequence}"
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_ecr_repository" "app" {
  name                 = "dotnet-app-${local.name_suffix}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

module "network" {
  source = "./modules/network"

  name_suffix          = local.name_suffix
  region               = var.region
  cluster_name         = "eks-${local.name_suffix}"
  vpc_cidr             = var.vpc_cidr
  azs                  = slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "alb" {
  source = "./modules/alb"

  name_suffix = local.name_suffix
  vpc_id      = module.network.vpc_id
}

module "s3" {
  source = "./modules/s3"

  name_suffix = local.name_suffix
  account_id  = data.aws_caller_identity.current.account_id
}

module "rds" {
  source = "./modules/rds"

  name_suffix                = local.name_suffix
  vpc_id                     = module.network.vpc_id
  private_subnet_ids         = module.network.private_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id, module.bastion.security_group_id]
}

module "bastion" {
  source = "./modules/bastion"

  name_suffix        = local.name_suffix
  vpc_id             = module.network.vpc_id
  subnet_id          = module.network.public_subnet_ids[0]
  key_name           = var.key_name
  allowed_ssh_cidrs  = var.allowed_ssh_cidrs
  instance_type      = var.bastion_instance_type
  kubernetes_version = var.kubernetes_version

  region                = var.region
  cluster_name          = module.eks.cluster_name
  lb_role_arn           = module.ingress_controller.role_arn
  alb_security_group_id = module.alb.security_group_id
  alb_name              = module.alb.alb_name
  app_port              = var.app_port
  health_check_path     = var.health_check_path

  s3_bucket_name     = module.s3.bucket_name
  rds_host           = module.rds.address
  rds_db             = module.rds.db_name
  rds_user           = module.rds.username
  rds_password       = module.rds.password
  ecr_repository_url = aws_ecr_repository.app.repository_url
  ecr_repository_arn = aws_ecr_repository.app.arn
}

module "eks" {
  source = "../eks"

  name_suffix        = local.name_suffix
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  node_instance_type = var.node_instance_type
  node_desired_size  = var.node_desired_size
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size

  bastion_role_arn = module.bastion.role_arn
  bastion_sg_id    = module.bastion.security_group_id
  alb_sg_id        = module.alb.security_group_id
  app_port         = var.app_port

  extra_node_policy_arns = {
    s3  = module.s3.policy_arn
    alb = module.ingress_controller.policy_arn
  }
}

module "ingress_controller" {
  source = "./modules/ingress-controller"

  name_suffix = local.name_suffix
}
