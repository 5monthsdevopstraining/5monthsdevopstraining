############################
# Control-plane logs (explicit log group so we control retention/cost)
############################
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.eks_log_retention_days
}

############################
# EKS cluster (PRIVATE API endpoint only)
############################
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.kubernetes_version # null = AWS default version

  # Access is managed with EKS access entries (IAM), not the old aws-auth ConfigMap.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = true
    endpoint_public_access  = false
    security_group_ids      = [aws_security_group.eks_api_access.id]
  }

  # Avoid the (more expensive) extended-support period of old versions.
  upgrade_policy {
    support_type = "STANDARD"
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_cloudwatch_log_group.eks,
  ]
}

############################
# Add-ons that must exist before the nodes join
############################
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

############################
# Worker nodes (managed node group in the PRIVATE subnets)
############################
resource "aws_launch_template" "nodes" {
  name_prefix = "${local.name_prefix}-nodes-"

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_disk_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # IMDSv2 only. Hop limit 1 stops pods from reading the node's IAM role.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.name_prefix}-eks-node" }
  }

  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "${local.name_prefix}-eks-node" }
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name_prefix}-nodes"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = aws_subnet.private[*].id

  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = var.node_instance_types
  capacity_type  = "ON_DEMAND"

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker,
    aws_iam_role_policy_attachment.eks_node_cni,
    aws_iam_role_policy.eks_node_ecr_pull,
    aws_route.private_nat, # nodes need the NAT Gateway to register
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
    aws_eks_addon.pod_identity_agent,
  ]

  lifecycle {
    # Let a cluster autoscaler or a manual scale change desired_size without a diff.
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# CoreDNS needs nodes to run on, so it is created after the node group.
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.main]
}

############################
# Who may use the cluster (EKS access entries)
############################
resource "aws_eks_access_entry" "jenkins" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.jenkins.arn
  type          = "STANDARD"
}

# Dev trade-off: Jenkins creates the namespace and installs the Load Balancer
# Controller, which are cluster-wide actions, so it gets cluster-admin.
# See docs/SECURITY-CHECKLIST.md for how to tighten this for production.
resource "aws_eks_access_policy_association" "jenkins" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_eks_access_entry.jenkins.principal_arn
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_access_entry" "additional_admins" {
  for_each = toset(var.additional_eks_admin_arns)

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "additional_admins" {
  for_each = toset(var.additional_eks_admin_arns)

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_eks_access_entry.additional_admins[each.value].principal_arn
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

############################
# Pod Identity: ties the Kubernetes service account to the app IAM role
############################
# The namespace and service account themselves are created by the Kubernetes
# manifests (kubernetes/namespace.yaml and service-account.yaml).
resource "aws_eks_pod_identity_association" "app" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = var.k8s_namespace
  service_account = var.k8s_service_account
  role_arn        = aws_iam_role.app.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}
