# eks/scripts/*.sh read these with "terraform output -raw <name>"

output "aws_region" {
  value = var.aws_region
}

output "aws_profile" {
  value = var.aws_profile
}

output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Private API endpoint - only reachable from inside the VPC"
  value       = aws_eks_cluster.this.endpoint
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "s3_bucket" {
  value = aws_s3_bucket.this.bucket
}

output "s3_upload_prefix" {
  value = local.upload_prefix
}

output "deployer_instance_id" {
  value = aws_instance.deployer.id
}

output "deployer_public_ip" {
  description = "SSH target for eks/scripts/ssh.sh and kubectl.sh (Elastic IP)"
  value       = aws_eip.deployer.public_ip
}

output "deployer_key_file" {
  value = abspath(local_sensitive_file.deployer_key.filename)
}

output "ssh_command" {
  value = "ssh -i ${abspath(local_sensitive_file.deployer_key.filename)} ec2-user@${aws_eip.deployer.public_ip}"
}

output "image_tag" {
  description = "Tag of the image deployed by the last terraform apply (Jenkins builds use <build>-<commit>)"
  value       = local.image_tag
}

########## Jenkins ##########

output "jenkins_url" {
  value = local.jenkins_url
}

output "jenkins_admin_user" {
  value = "admin"
}

output "jenkins_admin_password" {
  value     = random_password.jenkins_admin.result
  sensitive = true # terraform output -raw jenkins_admin_password
}

output "jenkins_job_url" {
  value = "${local.jenkins_url}job/${local.jenkins_job}/"
}

output "github_webhook_url" {
  description = "GitHub repo -> Settings -> Webhooks -> Add webhook: this Payload URL, content type application/json, just the push event"
  value       = "${local.jenkins_url}github-webhook/"
}

########## RDS ##########

output "rds_endpoint" {
  value = aws_db_instance.app.endpoint
}

output "rds_secret_arn" {
  description = "Secrets Manager secret with the RDS master username/password"
  value       = aws_db_instance.app.master_user_secret[0].secret_arn
}
