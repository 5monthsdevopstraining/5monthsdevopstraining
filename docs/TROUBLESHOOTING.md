# Troubleshooting

Where to look first: `terraform output`, then the AWS console, then logs.

## Terraform
| Problem | Cause / fix |
|---|---|
| `AccessDenied` / `UnauthorizedOperation` | See `docs/AWS-SETUP.md` section 6 (wrong profile, missing permission, or an SCP). |
| `explicit deny in a service control policy` | An AWS Organizations SCP blocks the action (often a disallowed region). Ask your administrator. |
| `InvalidParameterValue ... availability zone` | The two zones in `availability_zones` do not exist in your region. List them with `aws ec2 describe-availability-zones`. |
| `unsupported Kubernetes version` | You set `kubernetes_version`. Remove it or pick one from `aws eks describe-cluster-versions --region <region>`. |
| `RDS engine version not found` | Use `aws rds describe-db-engine-versions --engine postgres --query 'DBEngineVersions[].EngineVersion'` and set `db_engine_version`. |
| `Instance type not supported in AZ` | Change `node_instance_types` or the zones. |
| `terraform destroy` hangs on subnets/VPC/security groups | An ALB or ENI created by Kubernetes still exists. Run `bash scripts/cleanup.sh` (deletes the Ingress first) or delete the `k8s-sampleap-*` load balancer in the EC2 console. |
| Lost state / "already exists" errors | State is local in `terraform/`. Do not delete it while resources exist. |

## kubectl
| Problem | Cause / fix |
|---|---|
| `Unable to connect to the server: dial tcp ... i/o timeout` from your laptop | Expected: the API is private. Use the SSM shell on Jenkins and `setup-kubectl`. |
| `You must be logged in to the server (Unauthorized)` | The IAM role is not in the cluster access entries. Jenkins' role is added by Terraform; for other principals use `additional_eks_admin_arns`. |
| Nodes `NotReady` / no nodes | Check the node group in the EKS console (Health issues). Nodes need the NAT Gateway and the add-ons `vpc-cni` and `kube-proxy`. |

## Jenkins
| Problem | Cause / fix |
|---|---|
| `TargetNotConnected` when starting an SSM session | The instance has not registered with SSM yet (wait 3-5 min after boot). It needs outbound internet through the NAT Gateway and the `AmazonSSMManagedInstanceCore` policy. |
| `SessionManagerPlugin is not found` | Install the plugin (RUNBOOK step 2). |
| `http://localhost:8080` does not open | Keep the port-forward terminal running; check `sudo systemctl status jenkins` and `/var/log/jenkins-bootstrap.log` on the server. |
| Pipeline: `Missing platform setting` | The Jenkins service was not started with the Terraform-provided environment. Check `sudo systemctl show jenkins -p Environment`. |
| `permission denied ... docker.sock` | The `jenkins` user must be in the `docker` group and Jenkins restarted: `sudo usermod -aG docker jenkins && sudo systemctl restart jenkins`. |
| `dotnet: command not found` on the Jenkins host | Expected. Restore and build run inside `mcr.microsoft.com/dotnet/sdk:10.0`. Fix Docker pull/run, not a host SDK install. |
| ECR push: `tag invalid: The image tag ... already exists` | Repository tags are immutable; every build uses `<build>-<sha>`. Re-run the build (new number). |
| `no basic auth credentials` on push | ECR login failed; check that the Jenkins role policy still contains the ECR statements. |

## Application
| Problem | Cause / fix |
|---|---|
| Pods `ImagePullBackOff` | First deploy before any image exists, or the node role lost ECR pull rights. Run the pipeline; check `kubectl -n sample-app describe pod`. |
| Pods `CrashLoopBackOff` | `kubectl -n sample-app logs deploy/dotnet-api`. Common causes: the image is not the .NET 10 `dotnet.dll` build, or the probe path `/swagger/v1/swagger.json` is not returning 200. A missing bucket name does not crash the process; upload then returns 503. |
| Readiness probe failing | Probes call `GET /swagger/v1/swagger.json` on port 8080. That path is Swagger, which `Program.cs` always enables. The application has no `/health` endpoint. A database problem does not fail the probe; check `GET /api/database/connection` separately. |
| `AccessDenied` for Secrets Manager or S3 in the logs | The Pod Identity association must match **namespace `sample-app`** and **service account `dotnet-api`**. Check `aws eks list-pod-identity-associations --cluster-name <name>`. Restart the pods after changing it: `kubectl -n sample-app rollout restart deploy/dotnet-api`. |
| `Unable to get IAM security credentials` / no credentials | The `eks-pod-identity-agent` add-on must be running (`kubectl -n kube-system get ds eks-pod-identity-agent`). Pods only get credentials if they were created **after** the association. |
| DB error `no pg_hba.conf entry ... no encryption` | RDS requires TLS; the app already uses `SslMode=Require`. |
| Upload returns 400 | The form field must be named `file`, the file must be non-empty, and it must be 10 MB or smaller. Any file type is accepted. |
| Upload returns 503 | `S3:BucketName` is empty or still the `replace-with-your-s3-bucket` placeholder. The pipeline sets `S3__BucketName` from Terraform. |

## Load balancer
| Problem | Cause / fix |
|---|---|
| Ingress has no ADDRESS after 5 minutes | `kubectl -n kube-system logs deploy/aws-load-balancer-controller`. Typical causes: public subnets missing the tag `kubernetes.io/role/elb=1` (set by Terraform), or controller IAM errors (Pod Identity association for `kube-system/aws-load-balancer-controller`). |
| ALB returns 503 / 504 | Targets not healthy yet. In the EC2 console open the target group and read the reason; check the pods are `Ready`. |
| Browser cannot connect | The ALB is HTTP on port 80 and open to `inbound-cidrs` in `kubernetes/ingress.yaml`; check you did not restrict it to a different IP. |

## Handy commands (run on the Jenkins server via SSM)
```bash
kubectl -n sample-app get pods,svc,ingress,endpoints
kubectl -n sample-app describe deploy dotnet-api
kubectl -n sample-app logs deploy/dotnet-api --tail=50
kubectl -n kube-system get pods
kubectl get events -n sample-app --sort-by=.lastTimestamp | tail -20
```
