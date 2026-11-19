output "state_bucket" {
  value = "s3-tfstate-sample-dev-706016980953"
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "bastion_public_ip" {
  value = module.bastion.public_ip
}

output "jenkins_url" {
  description = "URL to access Jenkins on the Bastion host"
  value       = "http://${module.bastion.public_ip}:8080"
}

output "s3_bucket_name" {
  description = "Application S3 bucket name"
  value       = module.s3.bucket_name
}

output "ecr_repository_uri" {
  description = "ECR repository URI for the application image"
  value       = aws_ecr_repository.app.repository_url
}

output "rds_endpoint" {
  description = "PostgreSQL RDS endpoint"
  value       = module.rds.endpoint
}

output "alb_name" {
  description = "Name the ingress controller gives the ALB"
  value       = module.alb.alb_name
}

output "ssh_command" {
  value = "ssh -i key-sample-dev-apse2-public.pem ubuntu@${module.bastion.public_ip}"
}

output "get_alb_dns" {
  description = "Run on the bastion after deploying the app to get the ALB address"
  value       = "kubectl get ingress app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
