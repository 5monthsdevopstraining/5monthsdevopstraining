data "aws_ssm_parameter" "al2023_ami" {
  count = var.jenkins_ami_id == null ? 1 : 0
  name  = local.al2023_ami_ssm_parameter
}

locals {
  jenkins_ami_id = var.jenkins_ami_id != null ? var.jenkins_ami_id : data.aws_ssm_parameter.al2023_ami[0].value
}

resource "aws_instance" "jenkins" {
  ami                         = local.jenkins_ami_id
  instance_type               = var.jenkins_instance_type
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name
  associate_public_ip_address = false

  # IMDSv2 required.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = var.jenkins_root_volume_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/templates/jenkins-user-data.sh.tftpl", {
    aws_region          = var.aws_region
    cluster_name        = aws_eks_cluster.main.name
    vpc_id              = aws_vpc.main.id
    ecr_repository_url  = aws_ecr_repository.api.repository_url
    s3_bucket_name      = aws_s3_bucket.documents.bucket
    db_host             = aws_db_instance.postgres.address
    db_port             = aws_db_instance.postgres.port
    db_name             = var.db_name
    db_secret_arn       = aws_db_instance.postgres.master_user_secret[0].secret_arn
    k8s_namespace       = var.k8s_namespace
    k8s_service_account = var.k8s_service_account
  })
  user_data_replace_on_change = true

  tags = { Name = "${local.name_prefix}-jenkins" }

  # Package downloads need the NAT route; the pipeline needs the cluster,
  # the nodes and Jenkins' own cluster permissions to exist.
  depends_on = [
    aws_route.private_nat,
    aws_eks_node_group.main,
    aws_eks_access_policy_association.jenkins,
    aws_iam_role_policy.jenkins_permissions,
    aws_iam_role_policy_attachment.jenkins_ssm,
  ]
}
