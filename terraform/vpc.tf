############################
# VPC
############################
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-igw" }
}

############################
# Subnets
############################
# Public subnets: hold the NAT Gateway and the internet-facing ALB.
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false # Nothing in this project needs an auto-assigned public IP.

  tags = {
    Name                                          = "${local.name_prefix}-public-${count.index + 1}"
    "kubernetes.io/role/elb"                      = "1" # Internet-facing load balancers
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

# Private subnets: EKS nodes, Jenkins and RDS.
resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                                          = "${local.name_prefix}-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb"             = "1" # Internal load balancers
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

############################
# NAT Gateway (one, to keep cost down)
############################
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "${local.name_prefix}-nat-eip" }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = { Name = "${local.name_prefix}-nat" }

  depends_on = [aws_internet_gateway.main]
}

############################
# Route tables
############################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One private route table per private subnet (both use the single NAT Gateway).
resource "aws_route_table" "private" {
  count = 2

  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-private-rt-${count.index + 1}" }
}

resource "aws_route" "private_nat" {
  count = 2

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

############################
# S3 Gateway VPC Endpoint (free; keeps S3 traffic off the NAT Gateway)
############################
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = { Name = "${local.name_prefix}-s3-endpoint" }
}
