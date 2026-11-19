# Private EKS + Bastion + ALB Ingress (Terraform modules)

Region `ap-southeast-2`. Names follow `<resource>-<project>-<env>-<region>-<nn>`,
for example `eks-sample-dev-ap-southeast-2-01`. Change `project`, `environment` and
`sequence` in `terraform.tfvars` to rename everything.

## Layout

| Path | What it creates |
|---|---|
| `providers.tf` | AWS provider, S3 backend (`s3-tfstate-sample-dev-ap-southeast-2-01`) |
| `main.tf` | Wires the modules together |
| `modules/network` | VPC, public and private subnets (tagged for the ingress controller), IGW, NAT, route tables |
| `modules/alb` | Security group for the ALB (the ALB itself is created by the Ingress) |
| `modules/bastion` | Bastion EC2 (kubectl and helm installed), security group, IAM role |
| `../eks` | Private EKS cluster, node group, access entry for the bastion, security group rules |
| `modules/ingress-controller` | IAM role and policy (IRSA) for the AWS Load Balancer Controller |
| `scripts/bootstrap-state.sh` | Creates the state bucket |
| `../deploy/app.yaml` | Application Deployment, ClusterIP Service and Ingress |

## How traffic flows

Internet -> ALB (port 80) -> pod IP.

The AWS Load Balancer Controller is the ingress controller. It runs in the cluster,
reads the `Ingress` in `../deploy/app.yaml` and creates the ALB (named
`alb-sample-dev-ap-southeast-2-01`), its listener and a target group with
`target-type: ip`. It registers pod IPs directly, so there is no NodePort and no
hop through the nodes. The Service is `ClusterIP`.

The EKS API endpoint is private only, so Terraform does not install anything inside
the cluster. You install the controller and your app from the bastion.

## Steps

1. Export credentials (never put keys in files):
   ```
   export AWS_ACCESS_KEY_ID=...
   export AWS_SECRET_ACCESS_KEY=...
   export AWS_DEFAULT_REGION=ap-southeast-2
   ```
2. Create the state bucket: `./scripts/bootstrap-state.sh`
3. Create an EC2 key pair in `ap-southeast-2`, then copy `terraform.tfvars.example`
   to `terraform.tfvars` and set `key_name` and `allowed_ssh_cidrs`.
4. `terraform init && terraform apply` (about 15 minutes).
5. Copy the manifest to the bastion:
   `scp -i key.pem ../deploy/app.yaml ubuntu@<bastion_public_ip>:~`
6. SSH in (`terraform output ssh_command`) and run:
   ```
   connect-eks               # configures kubectl, lists nodes
   install-alb-controller    # installs the ingress controller with Helm
   deploy-app app.yaml       # applies Deployment, Service and Ingress
   kubectl get ingress app   # wait until ADDRESS shows the ALB DNS name
   ```
   The Jenkins pipeline substitutes the ECR image into `../deploy/app.yaml`.
   For manual deployment, build and push the image, then set `IMAGE_URI` before
   applying the manifest.
7. Open `http://<ALB DNS name>` (takes 2-3 minutes to become healthy).

If `connect-eks` fails right after apply, wait a minute: the bastion installs its
tools on first boot (`tail /var/log/cloud-init-output.log`).

## Notes

- HTTP only, as requested. HTTPS would need an ACM certificate, a 443 listener and
  the `alb.ingress.kubernetes.io/certificate-arn` annotation.
- The ALB security group is created by Terraform and attached through the Ingress
  `security-groups` annotation. The cluster security group allows it to reach the pods.
- Health check path and port are `health_check_path` and `app_port` in `terraform.tfvars`.
- Destroy: delete the Ingress first (`kubectl delete -f app.yaml`) so the controller
  removes the ALB, then `terraform destroy`.
- Requires Terraform 1.10 or newer (S3 native state locking).
