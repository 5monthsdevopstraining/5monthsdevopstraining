
pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
    }

    parameters {
        string(name: 'AWS_REGION', defaultValue: 'ap-south-1', description: 'AWS region')
        string(name: 'ECR_REPOSITORY_NAME', defaultValue: 'dotnet-app-dev/dotnet-app', description: 'ECR repository name')
        string(name: 'EKS_CLUSTER_NAME', defaultValue: 'dotnet-app-dev-eks', description: 'EKS cluster name')
        string(name: 'PROJECT_FILE', defaultValue: 'app/dotnet.csproj', description: 'Path to the .NET project file')
        string(name: 'APP_DLL', defaultValue: 'dotnet.dll', description: 'Application DLL name')
    }

    stages {
        stage('Validate') {
            steps {
                sh '''
                    test -f "${PROJECT_FILE}" || {
                        echo "Missing ${PROJECT_FILE}. Set PROJECT_FILE to the repository's .csproj file."
                        exit 1
                    }

                    command -v aws
                    command -v docker
                    command -v kubectl
                '''
            }
        }

        stage('Build and Push') {
            steps {
                sh '''
                    set -e

                    export AWS_DEFAULT_REGION="${AWS_REGION}"

                    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

                    ECR_URL=$(aws ecr describe-repositories \
                        --repository-names "${ECR_REPOSITORY_NAME}" \
                        --query 'repositories[0].repositoryUri' \
                        --output text)

                    test -n "${ECR_URL}"
                    test "${ECR_URL}" != "None"

                    GIT_COMMIT_SHORT=$(git rev-parse --short=12 HEAD)

                    IMAGE_TAG="build-${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"
                    IMAGE_URI="${ECR_URL}:${IMAGE_TAG}"

                    echo "${IMAGE_URI}" > .image-uri

                    aws ecr get-login-password --region "${AWS_REGION}" |
                        docker login \
                            --username AWS \
                            --password-stdin \
                            "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

                    docker build \
                        --build-arg PROJECT_FILE="${PROJECT_FILE}" \
                        --build-arg APP_DLL="${APP_DLL}" \
                        -t "${IMAGE_URI}" .

                    docker push "${IMAGE_URI}"

                    echo "Docker image successfully pushed: ${IMAGE_URI}"
                '''
            }
        }

        stage('Deploy to EKS') {
            steps {
                sh '''
                    set -e

                    export AWS_DEFAULT_REGION="${AWS_REGION}"

                    aws eks update-kubeconfig \
                        --name "${EKS_CLUSTER_NAME}" \
                        --region "${AWS_REGION}"

                    echo "Retrieving database credentials from AWS Secrets Manager..."
                    RDS_SECRET=$(aws secretsmanager get-secret-value \
                        --secret-id "dotnet-app-dev-postgres-credentials" \
                        --region "${AWS_REGION}" \
                        --query 'SecretString' \
                        --output text)

                    DB_HOST=$(echo "${RDS_SECRET}" | jq -r '.host')
                    DB_PORT=$(echo "${RDS_SECRET}" | jq -r '.port')
                    DB_NAME=$(echo "${RDS_SECRET}" | jq -r '.dbname')
                    DB_USER=$(echo "${RDS_SECRET}" | jq -r '.username')
                    DB_PASS=$(echo "${RDS_SECRET}" | jq -r '.password')
                    CONN_STRING="Host=${DB_HOST};Port=${DB_PORT};Database=${DB_NAME};Username=${DB_USER};Password=${DB_PASS};SSL Mode=Require;Trust Server Certificate=true"

                    kubectl create secret generic dotnet-app-db \
                        --from-literal=connection-string="${CONN_STRING}" \
                        --dry-run=client -o yaml | kubectl apply -f -

                    kubectl set env deployment/dotnet-app ConnectionStrings__Rds- >/dev/null 2>&1 || true

                    kubectl apply -f k8s/serviceaccount.yaml
                    kubectl apply -f k8s/service.yaml
                    kubectl apply -f k8s/deployment.yaml

                    IMAGE_URI=$(cat .image-uri)

                    kubectl set image deployment/dotnet-app \
                        dotnet-app="${IMAGE_URI}"

                    kubectl rollout status deployment/dotnet-app --timeout=5m

                    echo "Deployment completed successfully."

                    kubectl get pods -l app=dotnet-app
                    kubectl get service dotnet-app
                '''
            }
        }
    }

    post {
        cleanup {
            sh '''
                if test -f .image-uri; then
                    docker rmi "$(cat .image-uri)" >/dev/null 2>&1 || true
                fi
            '''
        }
    }
}
