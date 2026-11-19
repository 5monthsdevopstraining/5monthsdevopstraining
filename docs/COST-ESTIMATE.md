# Cost considerations

> **This architecture is NOT free-tier eligible.** Several resources bill every hour even when nothing is happening.
> The numbers below are **rough, approximate list prices (USD)** to show the order of magnitude. Prices differ by region
> (ap-south-1 is not the same as us-east-1) and change over time. Check the **AWS Pricing Calculator** and the pricing page of
> each service before you apply.

## What costs money
| Resource | How it is billed | Rough size of the cost |
|---|---|---|
| **EKS control plane** | per cluster-hour (~$0.10/h in standard support; much higher if the Kubernetes version is in *extended* support, which is why `upgrade_policy` is set to STANDARD) | ~$73 / month |
| **EC2 worker nodes** (2 x t3.medium) | per instance-hour, on-demand | ~$60 / month for both |
| **Jenkins EC2** (t3.medium) | per instance-hour | ~$30 / month |
| **NAT Gateway** | per hour **plus** per GB processed (images, packages, internet downloads) | ~$33 / month + ~$0.045 per GB |
| **RDS PostgreSQL** (db.t4g.micro, single-AZ) | per instance-hour + storage + backup storage beyond the DB size | ~$12 / month + ~$2-3 storage |
| **EBS volumes** (2 x 20 GiB nodes + 30 GiB Jenkins + RDS storage) | per GiB-month (gp3) | ~$6 / month |
| **Application Load Balancer** (created by the controller) | per hour + load-balancer capacity units | ~$16 / month + traffic |
| **Public IPv4 addresses** (NAT Gateway EIP, ALB nodes) | per address-hour | ~$3.65 / month each |
| **S3** | per GB-month stored + requests (+ versions kept) | cents for a learning project |
| **ECR** | per GB-month of images (lifecycle policy limits it) | cents |
| **CloudWatch Logs** (EKS control-plane logs, 7-day retention) | per GB ingested + stored | usually a few dollars |
| **Secrets Manager** (RDS-managed secret) | per secret-month + API calls | ~$0.40 / month |
| **Data transfer** | internet egress per GB; NAT processing; cross-AZ traffic | depends on use |

## Order of magnitude
Roughly **$250-300 per month, or about $0.35-0.40 per hour**, if left running. Learning for one afternoon costs a few
dollars; forgetting it for a month costs hundreds.

## Cost warning before `terraform apply`
`scripts/deploy.sh` prints this warning and requires you to type `yes`. If you run Terraform by hand, read the plan and
this page first.

## How to keep the bill small
* Run `bash scripts/cleanup.sh` as soon as you stop (it also removes the ALB, which Terraform does not manage).
* Set a **budget alert** in AWS Billing (for example $20 with email alerts) before the first apply.
* Use `node_desired_size = 1` for quick experiments (pods are spread over fewer nodes).
* Stop (not terminate) the Jenkins instance when not used; the NAT Gateway, EKS and RDS still bill.
* Check *Billing -> Cost Explorer* the next day, and look for leftover load balancers, Elastic IPs and snapshots.
