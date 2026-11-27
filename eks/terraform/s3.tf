# Private bucket for files uploaded through the app (/api/files/upload), under uploads/, written by the app pods
# (Pod Identity role in iam.tf)

resource "aws_s3_bucket" "this" {
  bucket        = "${local.name_prefix}-s3-eks-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # training: destroy even if it has files
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
