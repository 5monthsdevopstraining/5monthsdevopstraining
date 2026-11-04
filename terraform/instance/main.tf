locals {
  instance_name = "${var.name_prefix}-ec2-${var.purpose}"
  sg_name       = "${var.name_prefix}-sg-${var.purpose}"
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "this" {
  name_prefix = "${local.sg_name}-"
  description = "Security group for ${local.instance_name}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = local.sg_name
  })

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [tags, tags_all]
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = var.ingress_rules

  security_group_id            = aws_security_group.this.id
  description                  = each.value.description
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  cidr_ipv4                    = each.value.cidr_ipv4
  referenced_security_group_id = each.value.source_security_group_id

  tags = {
    Name = "${local.sg_name}-${each.key}"
  }
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "${local.sg_name}-egress-all"
  }
}

resource "aws_instance" "this" {
  ami                         = data.aws_ssm_parameter.al2023.insecure_value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = var.associate_public_ip
  private_ip                  = var.private_ip
  key_name                    = var.key_name

  user_data                   = var.user_data
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2          
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name = local.instance_name
  })

  lifecycle {
    ignore_changes = [ami, tags, tags_all]
  }
}

