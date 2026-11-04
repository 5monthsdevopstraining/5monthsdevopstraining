output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_name" {
  value = local.vpc_name
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "all_cidr_blocks" {
  description = "Primary + every secondary CIDR currently on the VPC"
  value       = [for a in data.aws_vpc.current.cidr_block_associations : a.cidr_block]
}

output "live_tags" {
  description = "VPC tags in AWS right now (includes console edits)"
  value       = data.aws_vpc.current.tags
}

output "public_subnet_ids" {
  value = { for k, s in aws_subnet.public : k => s.id }
}

output "private_subnet_ids" {
  value = { for k, s in aws_subnet.private : k => s.id }
}

output "igw_id" {
  value = aws_internet_gateway.this.id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.this.id
}

output "nat_public_ip" {
  value = aws_eip.nat.public_ip
}

output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}