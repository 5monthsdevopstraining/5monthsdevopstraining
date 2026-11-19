# EKS Terraform module

This module provisions the private EKS control plane, managed node group,
bastion access entry, and the security-group rules used by the application and
ALB. It is called by the root configuration in `../terraform/main.tf`.
