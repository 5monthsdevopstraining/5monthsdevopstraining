# S3 + RDS for the .NET app, an IAM role so the app EC2s can use them,
# and SSM parameters the deploy script reads to build the app's config.

data "aws_caller_identity" "current" {}

locals {
  app_param_path = "/${local.name_prefix}/app"
  s3_key_prefix  = "training-uploads"
}

########## S3 ##########

resource "aws_s3_bucket" "uploads" {
  bucket        = "${local.name_prefix}-uploads-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # training: let terraform destroy remove uploaded files too
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

########## RDS PostgreSQL ##########

resource "aws_db_subnet_group" "app" {
  name       = "${local.name_prefix}-dbsubnet-app"
  subnet_ids = values(module.vpc.private_subnet_ids) # needs 2 AZs
}

resource "aws_security_group" "rds" {
  name_prefix = "${local.name_prefix}-sg-rds-"
  description = "PostgreSQL from the app EC2s only"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "${local.name_prefix}-sg-rds"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_app" {
  for_each = {
    public  = module.public_ec2.security_group_id
    private = module.private_ec2.security_group_id
  }

  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL from ${each.key} app EC2"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = each.value
}

resource "aws_db_instance" "app" {
  identifier     = "${local.name_prefix}-rds-app"
  engine         = "postgres"
  engine_version = "17"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "appdb"
  username = "appadmin"
  # RDS generates the password and keeps it in Secrets Manager (never in tfstate)
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.app.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period = 0    # training: no backups
  skip_final_snapshot     = true # training: destroy without a snapshot
  apply_immediately       = true
}

########## Config for the deploy script (read on the EC2 at deploy time) ##########

resource "aws_ssm_parameter" "app" {
  for_each = {
    s3_bucket      = aws_s3_bucket.uploads.bucket
    s3_key_prefix  = local.s3_key_prefix
    rds_host       = aws_db_instance.app.address
    rds_port       = tostring(aws_db_instance.app.port)
    rds_database   = aws_db_instance.app.db_name
    rds_secret_arn = aws_db_instance.app.master_user_secret[0].secret_arn
  }

  name  = "${local.app_param_path}/${each.key}"
  type  = "String"
  value = each.value
}

########## IAM role for the app EC2s ##########

resource "aws_iam_role" "app_ec2" {
  name = "${local.name_prefix}-role-app-ec2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "app_ec2" {
  name = "app-s3-rds-config"
  role = aws_iam_role.app_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "UploadToBucket"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.uploads.arn}/${local.s3_key_prefix}/*"
      },
      {
        Sid      = "ReadAppConfig"
        Effect   = "Allow"
        Action   = ["ssm:GetParametersByPath", "ssm:GetParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.app_param_path}*"
      },
      {
        Sid      = "ReadDbPassword"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_db_instance.app.master_user_secret[0].secret_arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app_ec2" {
  name = "${local.name_prefix}-profile-app-ec2"
  role = aws_iam_role.app_ec2.name
}
