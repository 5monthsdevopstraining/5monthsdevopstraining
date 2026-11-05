output "name_prefix" {
  description = "Naming prefix used for every resource"
  value       = local.name_prefix
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_name" {
  value = module.vpc.vpc_name
}

output "vpc_cidr" {
  value = module.vpc.vpc_cidr
}

output "vpc_all_cidr_blocks" {
  description = "All CIDRs on the VPC, including ones added manually"
  value       = module.vpc.all_cidr_blocks
}

output "vpc_live_tags" {
  description = "VPC tags in AWS right now, including console edits"
  value       = module.vpc.live_tags
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "igw_id" {
  value = module.vpc.igw_id
}

output "nat_gateway_id" {
  value = module.vpc.nat_gateway_id
}

output "nat_public_ip" {
  value = module.vpc.nat_public_ip
}

output "public_ec2_name" {
  value = module.public_ec2.instance_name
}

output "public_ec2_public_ip" {
  value = module.public_ec2.public_ip
}

output "ssh_public_ec2" {
  value = "ssh -i ~/.ssh/sample-dev-key ec2-user@${module.public_ec2.public_ip}"
}

output "public_ec2_2_name" {
  value = module.public_ec2_2.instance_name
}

output "public_ec2_2_public_ip" {
  value = aws_eip.jenkins.public_ip
}

output "jenkins_url" {
  description = "Open in browser ~3 minutes after apply"
  value       = "http://${aws_eip.jenkins.public_ip}:8080"
}

output "jenkins_initial_password_cmd" {
  description = "Run this to get the Jenkins unlock password"
  value       = "ssh -i ~/.ssh/sample-dev-key ec2-user@${aws_eip.jenkins.public_ip} sudo cat /opt/jenkins_home/secrets/initialAdminPassword"
}

output "ssh_public_ec2_2" {
  value = "ssh -i ~/.ssh/sample-dev-key ec2-user@${aws_eip.jenkins.public_ip}"
}

output "private_ec2_private_ip" {
  value = module.private_ec2.private_ip
}

output "ssh_private_ec2" {
  value = "ssh -J ec2-user@${module.public_ec2.public_ip} ec2-user@${module.private_ec2.private_ip}"
}

output "public_app_url" {
  description = "App on Public 1 (after the Jenkins pipeline has deployed it)"
  value       = "http://${module.public_ec2.public_ip}"
}

output "public_ec2_private_ip" {
  description = "Use as PUBLIC_HOST in the Jenkinsfile (Jenkins reaches it inside the VPC)"
  value       = module.public_ec2.private_ip
}

output "jenkins_webhook_url" {
  description = "Payload URL for the GitHub webhook"
  value       = "http://${aws_eip.jenkins.public_ip}:8080/github-webhook/"
}

output "s3_bucket" {
  value = aws_s3_bucket.uploads.bucket
}

output "rds_endpoint" {
  value = aws_db_instance.app.address
}

output "rds_password_cmd" {
  description = "Show the RDS master password (stored in Secrets Manager)"
  value       = "aws secretsmanager get-secret-value --profile saranya --region ${var.aws_region} --secret-id ${aws_db_instance.app.master_user_secret[0].secret_arn} --query SecretString --output text"
}
