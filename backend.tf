terraform {
  # Supply the values from backend.hcl.example during `terraform init`.
  # S3 native lockfiles provide state locking for team usage.
  backend "s3" {}
}