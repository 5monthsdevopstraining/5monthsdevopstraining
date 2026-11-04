output "instance_id" {
  value = aws_instance.this.id
}

output "instance_name" {
  value = local.instance_name
}

output "public_ip" {
  value = aws_instance.this.public_ip
}

output "private_ip" {
  value = aws_instance.this.private_ip
}

output "security_group_id" {
  value = aws_security_group.this.id
}