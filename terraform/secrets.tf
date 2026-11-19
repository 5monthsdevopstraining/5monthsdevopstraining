# The database credentials live in AWS Secrets Manager. RDS creates and rotates
# the secret itself (manage_master_user_password = true in rds.tf), so the
# password never touches Terraform variables, code or Git.
#
# The secret contains JSON: {"username": "...", "password": "..."}.
# dotnet/Program.cs does not call Secrets Manager. It reads ConnectionStrings:Rds.
# Jenkins (below) reads this secret at deploy time and writes that connection
# string into a Kubernetes Secret. The host, port and database name are the
# non-secret values Terraform already passes to the Jenkins service.
#
# The application role may also read the same secret. The running process does
# not use that permission today; it is limited to this one secret.

data "aws_iam_policy_document" "app_db_secret" {
  statement {
    sid       = "ReadDatabaseCredentials"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_db_instance.postgres.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role_policy" "app_db_secret" {
  name   = "app-read-db-secret"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app_db_secret.json
}

resource "aws_iam_role_policy" "jenkins_db_secret" {
  name   = "jenkins-read-db-secret"
  role   = aws_iam_role.jenkins.id
  policy = data.aws_iam_policy_document.app_db_secret.json
}
