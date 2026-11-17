# Private EKS cluster: the Kubernetes API has NO public endpoint (only reachable inside the VPC),
# and the worker nodes run in the private subnets (outbound via the NAT gateway in vpc.tf).

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  access_config {
    # kubectl access is granted with EKS access entries (bottom of this file), no aws-auth ConfigMap
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = true
    endpoint_public_access  = false # private cluster
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_route_table_association.private,
  ]
}

# EKS creates a "cluster security group" used by the control plane, the managed nodes and the pods.
# Allow the deployer EC2 to reach the private API endpoint.
resource "aws_vpc_security_group_ingress_rule" "api_from_deployer" {
  security_group_id            = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description                  = "Kubernetes API from the EKS deployer EC2"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.deployer.id
}

########## Add-ons ##########

# Needed before nodes join: pod networking, kube-proxy and the Pod Identity agent
resource "aws_eks_addon" "core" {
  for_each = toset(["vpc-cni", "kube-proxy", "eks-pod-identity-agent"])

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# CoreDNS runs as pods, so it needs nodes first
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}

########## Worker nodes ##########

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.cluster_name}-ng-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = [var.node_instance_type]
  disk_size      = 20

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size] # allow manual scaling
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.core,
  ]
}

########## Pod Identity: Kubernetes service account -> IAM role ##########

resource "aws_eks_pod_identity_association" "app" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = local.k8s_namespace
  service_account = local.k8s_service_account
  role_arn        = aws_iam_role.app_pod.arn
}

resource "aws_eks_pod_identity_association" "lb_controller" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = local.lbc_namespace
  service_account = local.lbc_service_account
  role_arn        = aws_iam_role.lb_controller.arn
}

########## Who can use kubectl ##########

resource "aws_eks_access_entry" "deployer" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.deployer.arn
}

resource "aws_eks_access_policy_association" "deployer" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.deployer.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# Optional: let the identities you use in the AWS console see Kubernetes resources (nodes, pods)
resource "aws_eks_access_entry" "console" {
  for_each = toset(var.console_admin_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "console" {
  for_each = toset(var.console_admin_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.console[each.key].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
