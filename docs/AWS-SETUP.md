# AWS account setup (Ubuntu)

You never need to share credentials with anyone, including whoever helps you with this project.
Credentials stay on your machine in `~/.aws/`.

## 1. Install the AWS CLI v2
```bash
bash scripts/configure-aws.sh        # installs it if missing
aws --version
```
Manual installation steps are in `docs/RUNBOOK.md`, step 2.

## 2. Create the named profile `dotnet8-dev`

The profile name is only a local AWS CLI name used by the scripts. It is not the application framework. The deployed application is .NET 10 (`dotnet/dotnet.csproj`).
Best option - **IAM Identity Center (SSO)**, short-lived credentials:
```bash
aws configure sso --profile dotnet8-dev
aws sso login --profile dotnet8-dev       # repeat when the session expires
```
Fallback - an IAM user's access keys (long-lived: protect them, rotate them, delete them when done):
```bash
aws configure --profile dotnet8-dev
```
You are asked for: AWS Access Key ID, Secret Access Key, default region (for example `ap-south-1`), output format (`json`).

```bash
aws configure set region ap-south-1 --profile dotnet8-dev     # default region
export AWS_PROFILE=dotnet8-dev                                # use the profile in this terminal
```

## 3. Verify the identity
```bash
aws sts get-caller-identity
```
Shows Account, UserId and Arn. Make sure the account is the **development/sandbox** account you intend to use.

## 4. Required IAM permissions
The identity running Terraform must be allowed to create: VPC/EC2 networking, EC2 instances and launch templates, EKS,
IAM roles/policies/instance profiles, ECR, S3, RDS, Secrets Manager (RDS creates the secret), CloudWatch Logs and to read the
public SSM AMI parameter. It also needs to open SSM sessions to the Jenkins server.

* Easiest for a **personal sandbox account**: a dedicated user/role with `AdministratorAccess`, used only for this project.
* Tighter: start from `docs/terraform-deployer-policy.json` (service-level permissions; IAM actions limited to resources named
  `dotnet8-eks-*`). Adjust `project_name` in the policy if you change it. It is a starting point; if Terraform reports
  `AccessDenied`, add exactly the missing action.

For the **SSM session** from your laptop you also need `ssm:StartSession` (on the Jenkins instance and on the documents
`AWS-StartPortForwardingSession` / `SSM-SessionManagerRunShell`), `ssm:TerminateSession`, `ssm:SendCommand`,
`ssm:GetCommandInvocation`, `ssm:ListCommandInvocations` and `ec2:DescribeInstances` (used by `scripts/cleanup.sh`).

## 5. Check for AWS Organizations SCP restrictions
Service Control Policies (SCPs) can deny actions even if your IAM user is an administrator. Typical symptom:
`...with an explicit deny in a service control policy`.

```bash
aws organizations describe-organization
```
Shows whether your account belongs to an organization. `AWSOrganizationsNotInUseException` means it does not (no SCPs).
`AccessDeniedException` is normal in member accounts: you are not allowed to look.

If you can (management or delegated-admin account):
```bash
aws organizations list-policies --filter SERVICE_CONTROL_POLICY
aws organizations list-policies-for-target --target-id <account-id> --filter SERVICE_CONTROL_POLICY
aws organizations describe-policy --policy-id <p-xxxxxxxx>
```
List the SCPs, the ones attached to your account, and the JSON of one policy. Look for `Deny` statements on regions
(`aws:RequestedRegion`), on `eks:*`, `rds:*`, `iam:*`, or on creating internet gateways/NAT gateways.

If you cannot look: copy the **error text only** (never credentials) and send it to your cloud administrator, asking
which SCP blocks the action and whether your region is allowed.

## 6. Troubleshooting access denied errors
1. Read the error: it names the **action** (e.g. `eks:CreateCluster`) and the **identity** (the ARN).
2. Confirm you use the right profile: `aws sts get-caller-identity` (check `AWS_PROFILE`).
3. "explicit deny in a service control policy" -> an SCP blocks it (section 5). Your IAM policy cannot override it.
4. "no identity-based policy allows" -> add the action to your IAM policy (or use a broader sandbox role).
5. Region problems -> some organizations only allow specific regions; use an allowed region in `terraform.tfvars`.
6. Expired SSO session -> `aws sso login --profile dotnet8-dev`.
7. For difficult cases, find the event in **CloudTrail -> Event history**, filter by *Event name*, open the event and read `errorMessage`.
8. Test one permission quickly:
   ```bash
   aws iam simulate-principal-policy --policy-source-arn <your-user-or-role-arn> --action-names eks:CreateCluster
   ```
   (This evaluates IAM policies only, **not** SCPs.)
