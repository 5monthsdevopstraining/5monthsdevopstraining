output "vpc_id" {
  value = module.networking.vpc_id
}

output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "bastion_instance_id" {
  value = module.bastion.instance_id
}

output "ssm_connect_command" {
  value = "aws ssm start-session --target ${module.bastion.instance_id} --region ${var.region}"
}

output "kubeconfig_command" {
  description = "Run this on the bastion"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "rds_secret_arn" {
  value     = module.rds.secret_arn
  sensitive = true
}

output "s3_bucket_name" {
  value = module.s3.bucket_name
}

output "jenkins_url" {
  value = "http://${module.jenkins.public_ip}:8080"
}

output "sonarqube_url" {
  value = "http://${module.jenkins.public_ip}:9000"
}

output "jenkins_secret_arn" {
  value     = module.jenkins.secret_arn
  sensitive = true
}

output "app_s3_role_arn" {
  value = module.eks.app_s3_role_arn
}