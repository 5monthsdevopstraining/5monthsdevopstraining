variable "name_suffix" { type = string }
variable "kubernetes_version" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "node_instance_type" { type = string }
variable "node_desired_size" { type = number }
variable "node_min_size" { type = number }
variable "node_max_size" { type = number }
variable "bastion_role_arn" { type = string }
variable "bastion_sg_id" { type = string }
variable "alb_sg_id" { type = string }
variable "app_port" { type = number }
variable "extra_node_policy_arns" {
  type    = map(string)
  default = {}
}

# ---------------- Cluster ----------------
resource "aws_iam_role" "cluster" {
  name = "role-eks-cluster-${var.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = "eks-${var.name_suffix}"
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = false # private cluster: API reachable only inside the VPC
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# Bastion gets cluster-admin through an EKS access entry
resource "aws_eks_access_entry" "bastion" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.bastion_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "bastion" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.bastion_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.bastion]
}

# ---------------- Security group rules on the cluster SG ----------------
# The cluster (primary) security group is also attached to managed nodes and pods.
resource "aws_security_group_rule" "api_from_bastion" {
  type                     = "ingress"
  description              = "Bastion to private Kubernetes API"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  source_security_group_id = var.bastion_sg_id
}

resource "aws_security_group_rule" "app_from_alb" {
  type                     = "ingress"
  description              = "ALB to pods (IP targets)"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  source_security_group_id = var.alb_sg_id
}

# ---------------- Node group ----------------
resource "aws_iam_role" "node" {
  name = "role-eks-node-${var.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_iam_role_policy_attachment" "extra_node_policies" {
  for_each   = var.extra_node_policy_arns
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "ng-${var.name_suffix}"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_iam_role_policy_attachment.extra_node_policies
  ]
}

output "cluster_name" { value = aws_eks_cluster.this.name }
output "cluster_security_group_id" { value = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id }
