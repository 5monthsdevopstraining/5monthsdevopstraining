variable "name_suffix" { type = string }
variable "vpc_id" { type = string }

# The ALB itself is created by the AWS Load Balancer Controller from the Kubernetes
# Ingress (../deploy/app.yaml). Terraform owns the ALB's security group so the cluster
# security group can allow traffic from exactly this group.
resource "aws_security_group" "alb" {
  name        = "alb-sg-${var.name_suffix}"
  description = "ALB created by the ingress controller: allow HTTP from the internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "alb-sg-${var.name_suffix}" }
}

output "security_group_id" { value = aws_security_group.alb.id }
output "alb_name" { value = "alb-${var.name_suffix}" }
