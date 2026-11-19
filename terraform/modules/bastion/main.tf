variable "name_suffix" { type = string }
variable "vpc_id" { type = string }
variable "subnet_id" { type = string }
variable "key_name" { type = string }
variable "allowed_ssh_cidrs" { type = list(string) }
variable "instance_type" { type = string }
variable "kubernetes_version" { type = string }
variable "region" { type = string }
variable "cluster_name" { type = string }
variable "lb_role_arn" { type = string }
variable "alb_security_group_id" { type = string }
variable "alb_name" { type = string }
variable "app_port" { type = number }
variable "health_check_path" { type = string }
variable "s3_bucket_name" { type = string }
variable "rds_host" { type = string }
variable "rds_db" { type = string }
variable "rds_user" { type = string }
variable "rds_password" { type = string }
variable "ecr_repository_url" { type = string }
variable "ecr_repository_arn" { type = string }

data "aws_ami" "ubuntu_2404" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_security_group" "bastion" {
  name        = "bastion-sg-${var.name_suffix}"
  description = "Bastion: SSH and Jenkins UI from allowed CIDRs"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  ingress {
    description = "Jenkins Web UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "bastion-sg-${var.name_suffix}" }
}

resource "aws_iam_role" "bastion" {
  name = "role-bastion-${var.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "bastion_eks" {
  name = "policy-bastion-eks-${var.name_suffix}"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:AccessKubernetesApi"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
        Resource = var.ecr_repository_arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bastion" {
  name = "profile-bastion-${var.name_suffix}"
  role = aws_iam_role.bastion.name
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    region             = var.region
    cluster_name       = var.cluster_name
    kubernetes_version = var.kubernetes_version
    lb_role_arn        = var.lb_role_arn
    alb_sg_id          = var.alb_security_group_id
    alb_name           = var.alb_name
    app_port           = var.app_port
    health_check_path  = var.health_check_path
    vpc_id             = var.vpc_id
    s3_bucket_name     = var.s3_bucket_name
    rds_host           = var.rds_host
    rds_db             = var.rds_db
    rds_user           = var.rds_user
    rds_password       = var.rds_password
    ecr_repository_url = var.ecr_repository_url
  })

  user_data_replace_on_change = true

  tags = { Name = "bastion-${var.name_suffix}" }
}

output "public_ip" { value = aws_instance.bastion.public_ip }
output "role_arn" { value = aws_iam_role.bastion.arn }
output "security_group_id" { value = aws_security_group.bastion.id }
