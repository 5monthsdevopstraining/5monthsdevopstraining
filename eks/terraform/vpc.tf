# VPC for the private EKS cluster:
#   public subnets  (2 AZs) -> internet-facing ALB + NAT gateway + deployer EC2 (SSH jump box)
#   private subnets (2 AZs) -> EKS API endpoint ENIs, worker nodes, pods
# Nodes have no public IP; they reach the internet (ECR, EKS) through the NAT.

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # required for the private EKS endpoint

  tags = { Name = "${local.name_prefix}-vpc-eks" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name_prefix}-igw-eks" }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index) # 10.20.0.0/20, 10.20.16.0/20
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${local.name_prefix}-subnet-eks-public${count.index + 1}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1" # AWS Load Balancer Controller puts internet-facing ALBs here
  }
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 8) # 10.20.128.0/20, 10.20.144.0/20

  tags = {
    Name                              = "${local.name_prefix}-subnet-eks-private${count.index + 1}"
    Tier                              = "private"
    "kubernetes.io/role/internal-elb" = "1" # internal ALBs (not used by the sample app)
  }
}
# Extra subnet only for RDS (db.t4g.micro + gp3 needs capacity in ap-south-1c)
resource "aws_subnet" "rds_c" {
  vpc_id            = aws_vpc.this.id
  availability_zone = "ap-south-1c"
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, 12) # 10.20.192.0/20, no clash with existing subnets

  tags = {
    Name = "${local.name_prefix}-subnet-eks-rds-c"
    Tier = "database"
  }
}
########## Routing ##########

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${local.name_prefix}-rt-eks-public" }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One NAT gateway (cheaper for training; use one per AZ in production)
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${local.name_prefix}-eip-eks-nat" }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${local.name_prefix}-nat-eks" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = { Name = "${local.name_prefix}-rt-eks-private" }
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "rds_c" {
  subnet_id      = aws_subnet.rds_c.id
  route_table_id = aws_route_table.private.id
}
