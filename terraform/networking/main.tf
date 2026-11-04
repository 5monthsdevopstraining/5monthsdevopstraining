locals {
  vpc_name = "${var.name_prefix}-vpc-${var.purpose}"

  nat_subnet_key = sort(keys(var.public_subnets))[0]
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = local.vpc_name
  })

  lifecycle {
    prevent_destroy = false # set true in production
    ignore_changes  = [tags, tags_all]
  }
}

data "aws_vpc" "current" {
  id = aws_vpc.this.id
}

resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-subnet-${each.key}"
    Tier = "public"
  })

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-subnet-${each.key}"
    Tier = "private"
  })

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-igw-public"
  })

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-eip-nat"
  })

  depends_on = [aws_internet_gateway.this]

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[local.nat_subnet_key].id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-private"
  })

  depends_on = [aws_internet_gateway.this]

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rt-public"
  })

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [tags, tags_all]
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rt-private"
  })

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [tags, tags_all]
  }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}