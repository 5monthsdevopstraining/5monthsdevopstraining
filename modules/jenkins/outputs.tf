output "public_ip" { value = aws_instance.jenkins.public_ip }
output "instance_id" { value = aws_instance.jenkins.id }
output "security_group_id" { value = aws_security_group.jenkins.id }
output "role_arn" { value = aws_iam_role.jenkins.arn }
