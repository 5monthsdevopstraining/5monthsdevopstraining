output "aws_region" {
  description = "Region used by this deployment."
  value       = var.aws_region
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "Private API endpoint of the cluster (only reachable from inside the VPC)."
  value       = aws_eks_cluster.main.endpoint
}

output "ecr_repository_url" {
  description = "ECR repository URL for the .NET 10 application image."
  value       = aws_ecr_repository.api.repository_url
}

output "s3_bucket_name" {
  description = "Document storage bucket."
  value       = aws_s3_bucket.documents.bucket
}

output "rds_address" {
  description = "PostgreSQL host name (private)."
  value       = aws_db_instance.postgres.address
}

output "rds_database_name" {
  description = "Initial database name."
  value       = var.db_name
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the DB username and password."
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn
}

output "app_role_arn" {
  description = "IAM role assumed by the .NET pods through EKS Pod Identity."
  value       = aws_iam_role.app.arn
}

output "jenkins_instance_id" {
  description = "Instance ID of the Jenkins server (use it with SSM)."
  value       = aws_instance.jenkins.id
}

output "jenkins_ssm_shell_command" {
  description = "Open a shell on the Jenkins server through SSM."
  value       = "aws ssm start-session --target ${aws_instance.jenkins.id} --region ${var.aws_region}"
}

output "jenkins_ssm_port_forward_command" {
  description = "Forward Jenkins to http://localhost:8080 on your laptop."
  value       = "aws ssm start-session --target ${aws_instance.jenkins.id} --region ${var.aws_region} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"8080\"],\"localPortNumber\":[\"8080\"]}'"
}

output "kubernetes_namespace" {
  description = "Namespace of the application (matches kubernetes/namespace.yaml)."
  value       = var.k8s_namespace
}

output "kubernetes_service_account" {
  description = "Service account of the application (matches kubernetes/service-account.yaml)."
  value       = var.k8s_service_account
}
