# IAM for the AWS Load Balancer Controller. The controller runs in the cluster
# (installed by the Jenkins pipeline with Helm) and creates the internet-facing
# Application Load Balancer when it sees kubernetes/ingress.yaml.
#
# The policy file is the official one published by the controller project,
# matching controller v2.8.2 (see docs/RUNBOOK.md if you upgrade the controller).

resource "aws_iam_role" "lb_controller" {
  name               = "${local.name_prefix}-lb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_policy" "lb_controller" {
  name        = "${local.name_prefix}-lb-controller-policy"
  description = "Official AWS Load Balancer Controller permissions"
  policy      = file("${path.module}/policies/aws-lb-controller-iam-policy.json")
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

resource "aws_eks_pod_identity_association" "lb_controller" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lb_controller.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}
