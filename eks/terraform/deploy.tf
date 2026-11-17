# First deploy of the app as part of "terraform apply", over SSH to the deployer EC2
# (after that, Jenkins deploys every git push - see jenkins.tf and eks/Jenkinsfile):
#   1. upload app/, eks/k8s/ and eks/scripts/deploy-app.sh from your laptop (file provisioner = scp),
#      in the same layout as the git repo, so Jenkins runs the very same script from its checkout
#   2. run deploy-app.sh: docker build + push to ECR, AWS Load Balancer Controller, ConfigMap,
#      RDS Secret, Deployment, Service, Ingress (ALB), wait until the app answers
# It runs again when your local app source, the manifests, the script, the settings or the EC2 change.

locals {
  app_dir     = "${path.module}/../../app"
  k8s_dir     = "${path.module}/../k8s"
  deploy_file = "${path.module}/../scripts/deploy-app.sh"
  remote_dir  = "/home/ec2-user/eks-deploy" # = repo root layout: app/, eks/k8s/, eks/scripts/

  # Hash of everything that ends up in the image or the cluster (bin/ and obj/ are build output)
  app_files = sort([for f in fileset(local.app_dir, "**") : f
  if !can(regex("^(bin|obj|\\.vs|build-check)/", f))])
  deploy_hash = sha1(join(",", concat(
    [for f in local.app_files : filesha1("${local.app_dir}/${f}")],
    [for f in sort(fileset(local.k8s_dir, "*.yaml")) : filesha1("${local.k8s_dir}/${f}")],
    [filesha1(local.deploy_file)],
  )))
  image_tag = "tf-${substr(local.deploy_hash, 0, 12)}" # new source -> new tag -> pods roll

  ssh_connection = {
    type        = "ssh"
    host        = aws_eip.deployer.public_ip
    user        = "ec2-user"
    private_key = tls_private_key.deployer.private_key_openssh3
  }
}

resource "terraform_data" "deploy" {
  triggers_replace = {
    deploy_hash = local.deploy_hash
    setup_id    = terraform_data.deployer_setup.id # new EC2 or new settings
  }

  connection {
    type        = local.ssh_connection.type
    host        = local.ssh_connection.host
    user        = local.ssh_connection.user
    private_key = local.ssh_connection.private_key
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "rm -rf ${local.remote_dir} && mkdir -p ${local.remote_dir}/app ${local.remote_dir}/eks/k8s ${local.remote_dir}/eks/scripts",
    ]
  }

  # 1. copy the source and manifests (a trailing "/" copies the folder contents)
  provisioner "file" {
    source      = "${local.app_dir}/"
    destination = "${local.remote_dir}/app"
  }

  provisioner "file" {
    source      = "${local.k8s_dir}/"
    destination = "${local.remote_dir}/eks/k8s"
  }

  provisioner "file" {
    source      = local.deploy_file
    destination = "${local.remote_dir}/eks/scripts/deploy-app.sh"
  }

  # 2. build + deploy (first run ~5-8 min: the .NET image is built from scratch)
  provisioner "remote-exec" {
    inline = [
      "rm -rf ${local.remote_dir}/app/bin ${local.remote_dir}/app/obj",
      "sudo bash ${local.remote_dir}/eks/scripts/deploy-app.sh ${local.image_tag}",
    ]
  }

  depends_on = [
    aws_eks_node_group.this,
    aws_eks_addon.coredns,
    aws_eks_access_policy_association.deployer,
    aws_eks_pod_identity_association.app,
    aws_eks_pod_identity_association.lb_controller,
    aws_vpc_security_group_ingress_rule.api_from_deployer,
    aws_vpc_security_group_ingress_rule.rds_from_pods,
    aws_iam_role_policy.deployer,
    aws_iam_role_policy.lb_controller,
    aws_route_table_association.private,
    terraform_data.ingress_cleanup,
  ]
}

# "terraform destroy" first deletes the Ingress over SSH, so the AWS Load Balancer Controller removes the
# ALB and its security groups. Terraform doesn't know about them and they would block deleting the VPC.
# Kept separate from terraform_data.deploy so a redeploy doesn't delete the ALB.
resource "terraform_data" "ingress_cleanup" {
  input = local.ssh_connection

  provisioner "remote-exec" {
    when       = destroy
    on_failure = continue

    connection {
      type        = self.input.type
      host        = self.input.host
      user        = self.input.user
      private_key = self.input.private_key
    }

    inline = [
      "sudo systemctl stop jenkins || true", # no new deploy while tearing down
      "kubectl delete ingress sample-app -n sample-app --ignore-not-found --wait --timeout 5m || true",
      "helm uninstall aws-load-balancer-controller -n kube-system --wait --timeout 3m || true",
    ]
  }

  # Destroyed (and its provisioner run) while everything it needs still exists: Terraform destroys
  # these only AFTER this resource. Without the deployer's egress rule it can't reach the EKS API,
  # and without the LB controller's add-ons/role the ALB is never removed.
  depends_on = [
    aws_eks_node_group.this,
    aws_eks_addon.core,
    aws_eks_access_policy_association.deployer,
    aws_vpc_security_group_ingress_rule.api_from_deployer,
    aws_vpc_security_group_ingress_rule.deployer_ssh,
    aws_vpc_security_group_egress_rule.deployer_all,
    aws_iam_role_policy.deployer,
    aws_iam_role_policy.lb_controller,
    aws_eks_pod_identity_association.lb_controller,
    aws_route_table_association.public,
    aws_route_table_association.private,
    aws_nat_gateway.this,
  ]
}

