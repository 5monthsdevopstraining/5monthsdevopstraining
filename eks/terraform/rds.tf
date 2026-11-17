# PostgreSQL for the app (GET /api/database/connection), in the private subnets.
# RDS generates the master password and keeps it in Secrets Manager (never in the Terraform state).
# eks/scripts/deploy-app.sh reads it at deploy time and stores the connection string in the
# Kubernetes Secret "sample-app-db", which the pods get as ConnectionStrings__Rds.

resource "aws_db_subnet_group" "app" {
  name       = "${local.name_prefix}-dbsubnet-eks-app"
  subnet_ids = aws_subnet.private[*].id # 2 AZs
}

resource "aws_security_group" "rds" {
  name_prefix = "${local.name_prefix}-sg-eks-rds-"
  description = "PostgreSQL from the EKS nodes/pods only"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${local.name_prefix}-sg-eks-rds" }

  lifecycle {
    create_before_destroy = true
  }
}

# Managed nodes (and so the pods, with the VPC CNI) use the EKS cluster security group
resource "aws_vpc_security_group_ingress_rule" "rds_from_pods" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL from EKS nodes and pods"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

resource "aws_db_instance" "app" {
  identifier     = "${local.name_prefix}-rds-eks-app"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name                     = "appdb"
  username                    = "appadmin"
  manage_master_user_password = true # password lives in Secrets Manager

  db_subnet_group_name   = aws_db_subnet_group.app.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period = 0    # training: no backups
  skip_final_snapshot     = true # training: destroy without a snapshot
  apply_immediately       = true
}
