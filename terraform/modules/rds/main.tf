variable "name_suffix" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "allowed_security_group_ids" { type = list(string) }
variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

resource "aws_db_subnet_group" "this" {
  name       = "dbsng-${var.name_suffix}"
  subnet_ids = var.private_subnet_ids

  tags = { Name = "dbsng-${var.name_suffix}" }
}

resource "aws_security_group" "rds" {
  name        = "rds-sg-${var.name_suffix}"
  description = "PostgreSQL RDS: allow port 5432 from EKS and Bastion"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allowed_security_group_ids
    content {
      description     = "PostgreSQL from security group"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "rds-sg-${var.name_suffix}" }
}

resource "random_password" "db_password" {
  length  = 16
  special = false # Avoid special characters for clean connection string formatting
}

resource "aws_db_instance" "this" {
  identifier        = "rds-${var.name_suffix}"
  allocated_storage = 20
  storage_type      = "gp3"
  engine            = "postgres"
  engine_version    = "16.11"
  instance_class    = var.db_instance_class

  db_name  = "appdb"
  username = "dbadmin"
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  skip_final_snapshot     = true
  deletion_protection     = false
  publicly_accessible     = false
  backup_retention_period = 0

  tags = { Name = "rds-${var.name_suffix}" }
}

output "endpoint" {
  value = aws_db_instance.this.endpoint
}

output "address" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "username" {
  value = aws_db_instance.this.username
}

output "password" {
  value     = random_password.db_password.result
  sensitive = true
}

output "security_group_id" {
  value = aws_security_group.rds.id
}
