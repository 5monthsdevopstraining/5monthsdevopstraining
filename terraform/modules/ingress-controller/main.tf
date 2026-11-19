variable "name_suffix" { type = string }

variable "controller_version" {
  description = "AWS Load Balancer Controller release whose IAM policy is used"
  type        = string
  default     = "v2.8.2"
}

# Official IAM policy published by the controller project
data "http" "policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${var.controller_version}/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "controller" {
  name   = "policy-alb-controller-${var.name_suffix}"
  policy = data.http.policy.response_body
}

output "policy_arn" { value = aws_iam_policy.controller.arn }
output "role_arn" { value = "" }
