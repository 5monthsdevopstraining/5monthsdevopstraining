########## EKS control plane ##########

resource "aws_iam_role" "cluster" {
  name = "${local.cluster_name}-role-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

########## Worker nodes ##########

resource "aws_iam_role" "node" {
  name = "${local.cluster_name}-role-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly", # pull the app image from ECR
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

########## Pod Identity roles ##########

locals {
  pod_identity_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# App pods: upload files to the S3 bucket (s3.tf), uploads/ folder only
resource "aws_iam_role" "app_pod" {
  name               = "${local.cluster_name}-role-app-pod"
  assume_role_policy = local.pod_identity_trust
}

resource "aws_iam_role_policy" "app_pod" {
  name = "app-s3-upload"
  role = aws_iam_role.app_pod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "UploadToBucket"
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.this.arn}/${local.upload_prefix}/*"
    }]
  })
}

# AWS Load Balancer Controller (creates the ALB for k8s/04-ingress.yaml)
resource "aws_iam_role" "lb_controller" {
  name               = "${local.cluster_name}-role-lbc"
  assume_role_policy = local.pod_identity_trust
}

# Official policy: kubernetes-sigs/aws-load-balancer-controller v3.6.2 docs/install/iam_policy.json
resource "aws_iam_role_policy" "lb_controller" {
  name   = "aws-load-balancer-controller"
  role   = aws_iam_role.lb_controller.id
  policy = file("${path.module}/policies/lb-controller-iam-policy.json")
}

########## Deployer EC2 (docker build/push + kubectl/helm, driven over SSH by terraform/deploy.tf) ##########

resource "aws_iam_role" "deployer" {
  name = "${local.cluster_name}-role-deployer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "deployer" {
  name = "eks-deploy"
  role = aws_iam_role.deployer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = aws_ecr_repository.app.arn
      },
      {
        Sid      = "Kubeconfig"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = aws_eks_cluster.this.arn
      },
      {
        Sid      = "ReadDbPassword" # deploy-app.sh builds the app's RDS connection string
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_db_instance.app.master_user_secret[0].secret_arn
      },
    ]
  })
}

resource "aws_iam_instance_profile" "deployer" {
  name = "${local.cluster_name}-profile-deployer"
  role = aws_iam_role.deployer.name
}
