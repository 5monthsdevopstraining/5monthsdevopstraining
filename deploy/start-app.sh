#!/bin/bash
# Runs on each app EC2 (copied there by Jenkins).
# Reads S3/RDS settings from SSM + the DB password from Secrets Manager (via the EC2's IAM role),
# writes them to a root-only env file and (re)starts the app container with it.
# Usage: start-app.sh <app_name> <image> <host_port> <aws_region> <ssm_param_path>
set -euo pipefail

APP_NAME=$1
IMAGE=$2
HOST_PORT=$3
REGION=$4
PARAM_PATH=$5

param() {
  aws ssm get-parameter --region "$REGION" --name "$PARAM_PATH/$1" --query Parameter.Value --output text
}

S3_BUCKET=$(param s3_bucket)
S3_PREFIX=$(param s3_key_prefix)
DB_HOST=$(param rds_host)
DB_PORT=$(param rds_port)
DB_NAME=$(param rds_database)

SECRET=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$(param rds_secret_arn)" \
  --query SecretString --output text)
DB_USER=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["username"])' <<<"$SECRET")
DB_PASS=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])' <<<"$SECRET")

ENV_FILE=/etc/$APP_NAME.env
sudo install -m 600 -o root -g root /dev/null "$ENV_FILE"
sudo tee "$ENV_FILE" >/dev/null <<EOF
AWS__Region=$REGION
S3__BucketName=$S3_BUCKET
S3__KeyPrefix=$S3_PREFIX
ConnectionStrings__Rds=Host=$DB_HOST;Port=$DB_PORT;Database=$DB_NAME;Username=$DB_USER;Password="$DB_PASS";SSL Mode=Require
EOF

sudo docker rm -f "$APP_NAME" 2>/dev/null || true
sudo docker run -d --name "$APP_NAME" --restart unless-stopped \
  -p "$HOST_PORT:8080" --env-file "$ENV_FILE" "$IMAGE"

echo "$APP_NAME started on port $HOST_PORT (bucket: $S3_BUCKET, db: $DB_HOST)"
