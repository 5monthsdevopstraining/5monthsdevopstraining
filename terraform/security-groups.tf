############################
# Jenkins server
############################
# No inbound rules at all: Jenkins is reached through AWS Systems Manager
# (SSM) port forwarding, which does not need any open port.
resource "aws_security_group" "jenkins" {
  name        = "${local.name_prefix}-jenkins-sg"
  description = "Jenkins server - no inbound, outbound via NAT"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-jenkins-sg" }
}

resource "aws_vpc_security_group_egress_rule" "jenkins_all_out" {
  security_group_id = aws_security_group.jenkins.id
  description       = "Outbound to the internet through NAT (packages, GitHub, SSM, ECR) and to the VPC (EKS API)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

############################
# EKS control plane: extra SG that lets Jenkins reach the PRIVATE API endpoint
############################
resource "aws_security_group" "eks_api_access" {
  name        = "${local.name_prefix}-eks-api-access-sg"
  description = "Allows Jenkins to call the private EKS API endpoint"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-eks-api-access-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "eks_api_from_jenkins" {
  security_group_id            = aws_security_group.eks_api_access.id
  description                  = "Kubernetes API (HTTPS) from Jenkins"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.jenkins.id
}

############################
# RDS: only the EKS workload may connect
############################
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "PostgreSQL - only from the EKS workload"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-rds-sg" }
}

# The application pods run with the cluster security group (EKS attaches it to
# every managed node and pod ENI), so it identifies "the application workload".
resource "aws_vpc_security_group_ingress_rule" "rds_from_eks_workload" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL from the EKS cluster security group"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}
