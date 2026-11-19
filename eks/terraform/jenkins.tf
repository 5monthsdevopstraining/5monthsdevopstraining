# Jenkins on the deployer EC2 (installed by scripts/deployer.sh). Terraform configures it over SSH:
#   /etc/eks-deploy.env       -> cluster, ECR, S3 and RDS settings read by eks/scripts/deploy-app.sh
#   /var/lib/jenkins/casc.yaml -> admin user + the pipeline job (templates/jenkins-casc.yaml.tftpl)
# The job runs eks/Jenkinsfile on every push to var.github_branch (GitHub webhook, or polling every 2 min).
#   UI:      terraform output jenkins_url   (user admin, password: terraform output -raw jenkins_admin_password)
#   Webhook: terraform output github_webhook_url
# ss
resource "random_password" "jenkins_admin" {
  length  = 20
  special = false
}

locals {
  jenkins_url = "http://${local.deployer_ip}:8080/"
  jenkins_job = "eks-sample-app"

  # Settings for eks/scripts/deploy-app.sh (no secrets: the DB password is read from Secrets Manager)
  deploy_env = <<-EOT
    AWS_REGION=${var.aws_region}
    CLUSTER=${aws_eks_cluster.this.name}
    VPC_ID=${aws_vpc.this.id}
    BUCKET=${aws_s3_bucket.this.bucket}
    UPLOAD_PREFIX=${local.upload_prefix}
    ECR_REPO=${aws_ecr_repository.app.repository_url}
    RDS_HOST=${aws_db_instance.app.address}
    RDS_PORT=${aws_db_instance.app.port}
    RDS_DATABASE=${aws_db_instance.app.db_name}
    RDS_SECRET_ARN=${aws_db_instance.app.master_user_secret[0].secret_arn}
  EOT

  jenkins_casc = templatefile("${path.module}/templates/jenkins-casc.yaml.tftpl", {
    admin_password = random_password.jenkins_admin.result
    jenkins_url    = local.jenkins_url
    job_name       = local.jenkins_job
    repo_url       = var.github_repo_url
    branch         = var.github_branch
  })
}

resource "terraform_data" "deployer_setup" {
  triggers_replace = {
    instance_id = aws_instance.deployer.id
    config      = sha1("${local.deploy_env}${local.jenkins_casc}")
  }

  connection {
    type        = "ssh"
    host        = local.deployer_ip
    user        = "ec2-user"
    private_key = tls_private_key.deployer.private_key_openssh
    timeout     = "10m" # the instance may still be booting
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for user data (docker, kubectl, helm, Jenkins)...'",
      "for i in $(seq 1 90); do [ -f /var/lib/eks-deployer-ready ] && break; sleep 10; done",
      "[ -f /var/lib/eks-deployer-ready ] || { sudo tail -30 /var/log/user-data.log; exit 1; }",
    ]
  }

  provisioner "file" {
    content     = local.deploy_env
    destination = "/tmp/eks-deploy.env"
  }

  provisioner "file" {
    content     = local.jenkins_casc
    destination = "/tmp/casc.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo install -m 0644 -o root -g root /tmp/eks-deploy.env /etc/eks-deploy.env",
      "sudo install -m 0600 -o jenkins -g jenkins /tmp/casc.yaml /var/lib/jenkins/casc.yaml",
      "rm -f /tmp/eks-deploy.env /tmp/casc.yaml",
      "sudo systemctl restart jenkins",
      "echo 'Waiting for Jenkins to start...'",
      "for i in $(seq 1 60); do curl -s -o /dev/null -w '%%{http_code}' http://localhost:8080/login | grep -q 200 && break; sleep 5; done",
      "curl -fsS -o /dev/null http://localhost:8080/login && echo 'Jenkins is up'",
    ]
  }

  depends_on = [
    aws_eip_association.deployer, # SSH goes to the static IP
    aws_vpc_security_group_ingress_rule.deployer_ssh,
    aws_route_table_association.public,
  ]
}
