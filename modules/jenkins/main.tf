data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "jenkins" {
  name_prefix = "${var.name}-"
  description = "Jenkins web and agent access"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_iam_role" "jenkins" {
  name = "${var.name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "jenkins" {
  name = "${var.name}-deploy"
  role = aws_iam_role.jenkins.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster", "eks:ListClusters"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.jenkins.arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.rds_secret_arn == "" ? aws_secretsmanager_secret.jenkins.arn : var.rds_secret_arn
      }
    ]
  })
}

resource "random_password" "jenkins" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+"
}

resource "aws_secretsmanager_secret" "jenkins" {
  name                    = "${var.name}-admin"
  recovery_window_in_days = 7
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "jenkins" {
  secret_id = aws_secretsmanager_secret.jenkins.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.jenkins.result
  })
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.name}-profile"
  role = aws_iam_role.jenkins.name
}

locals {
  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    dnf update -y
    dnf install -y docker git amazon-ssm-agent
    systemctl enable --now docker
    systemctl enable --now amazon-ssm-agent

    if ! swapon --show | grep -q /swapfile; then
      fallocate -l 4G /swapfile
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    sysctl -w vm.max_map_count=262144
    echo 'vm.max_map_count=262144' >> /etc/sysctl.conf

    mkdir -p /opt/jenkins
    git clone --branch ${var.branch} --single-branch ${var.repository_url} /opt/jenkins
    cd /opt/jenkins

    docker network create ci-net >/dev/null 2>&1 || true

    docker build -f Dockerfile.jenkins -t local/jenkins:lts .
    docker volume create jenkins_home
    docker rm -f jenkins >/dev/null 2>&1 || true
    docker run -d --name jenkins --restart unless-stopped \
      --network ci-net \
      -p 8080:8080 -p 50000:50000 \
      -v jenkins_home:/var/jenkins_home \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v /opt/jenkins/jenkins:/var/jenkins_home/casc_configs:ro \
      -e JAVA_OPTS="-Xms256m -Xmx512m" \
      local/jenkins:lts

    docker volume create sonarqube_data
    docker volume create sonarqube_extensions
    docker volume create sonarqube_logs
    docker rm -f sonarqube >/dev/null 2>&1 || true
    docker run -d --name sonarqube --restart unless-stopped \
      --network ci-net \
      -p 9000:9000 \
      -v sonarqube_data:/opt/sonarqube/data \
      -v sonarqube_extensions:/opt/sonarqube/extensions \
      -v sonarqube_logs:/opt/sonarqube/logs \
      -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
      -e SONAR_WEB_JAVAOPTS="-Xms128m -Xmx384m" \
      -e SONAR_CE_JAVAOPTS="-Xms128m -Xmx384m" \
      -e SONAR_SEARCH_JAVAOPTS="-Xms256m -Xmx512m" \
      sonarqube:lts-community

    chmod 666 /var/run/docker.sock
  EOF
}

resource "aws_instance" "jenkins" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name
  associate_public_ip_address = true
  key_name                    = var.key_name
  user_data                   = local.user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(var.tags, { Name = var.name })
}
