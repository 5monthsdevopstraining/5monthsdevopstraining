variable "name_suffix" {
  description = "Name suffix for resources"
  type        = string
}

variable "account_id" {
  description = "AWS Account ID for globally unique bucket naming"
  type        = string
}

resource "aws_s3_bucket" "app" {
  bucket        = "s3-app-${var.name_suffix}-${var.account_id}"
  force_destroy = true

  tags = {
    Name = "s3-app-${var.name_suffix}"
  }
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM policy for EKS workloads to access this bucket
resource "aws_iam_policy" "app_s3" {
  name        = "policy-app-s3-${var.name_suffix}"
  description = "Permissions for application pods to access the application S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [aws_s3_bucket.app.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = ["${aws_s3_bucket.app.arn}/*"]
      }
    ]
  })
}

output "bucket_name" {
  value = aws_s3_bucket.app.id
}

output "bucket_arn" {
  value = aws_s3_bucket.app.arn
}

output "policy_arn" {
  value = aws_iam_policy.app_s3.arn
}
