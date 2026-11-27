pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timeout(time: 40, unit: 'MINUTES')
    }

    parameters {
        string(name: 'AWS_REGION', defaultValue: 'ap-south-1', description: 'AWS region')
        string(name: 'ECR_REPOSITORY_NAME', defaultValue: 'dotnet-app-dev/dotnet-app', description: 'ECR repository name')
        string(name: 'EKS_CLUSTER_NAME', defaultValue: 'dotnet-app-dev-eks', description: 'EKS cluster name')
        string(name: 'PROJECT_FILE', defaultValue: 'app/dotnet.csproj', description: 'Path to the .NET project file')
        string(name: 'APP_DLL', defaultValue: 'dotnet.dll', description: 'Application DLL name')
        string(name: 'SONARQUBE_URL', defaultValue: 'http://sonarqube:9000', description: 'SonarQube server URL')
    }

    environment {
        AWS_REGION          = "${params.AWS_REGION ?: 'ap-south-1'}"
        ECR_REPOSITORY_NAME = "${params.ECR_REPOSITORY_NAME ?: 'dotnet-app-dev/dotnet-app'}"
        EKS_CLUSTER_NAME    = "${params.EKS_CLUSTER_NAME ?: 'dotnet-app-dev-eks'}"
        PROJECT_FILE        = "${params.PROJECT_FILE ?: 'app/dotnet.csproj'}"
        APP_DLL             = "${params.APP_DLL ?: 'dotnet.dll'}"
        SONARQUBE_URL       = "${params.SONARQUBE_URL ?: 'http://sonarqube:9000'}"
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
                    command -v trivy
                    trivy --version
                '''
            }
        }

        stage('Trivy FS Scan') {
            steps {
                sh '''
                    set -e
                    echo "Running Trivy filesystem vulnerability, secret, and misconfiguration scan..."
                    trivy fs \
                        --scanners vuln,secret,misconfig \
                        --severity HIGH,CRITICAL \
                        --no-progress \
                        --exit-code 0 \
                        -o trivy-fs-report.txt \
                        .
                    cat trivy-fs-report.txt
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-fs-report.txt', allowEmptyArchive: true
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                sh '''
                    set -e
                    echo "Checking SonarQube availability at ${SONARQUBE_URL}..."
                    SONAR_UP="false"
                    for i in $(seq 1 12); do
                        if curl -sf "${SONARQUBE_URL}/api/system/status" | grep -q '"status":"UP"'; then
                            SONAR_UP="true"
                            break
                        fi
                        echo "Waiting for SonarQube to become ready ($i/12)..."
                        sleep 10
                    done

                    if [ "${SONAR_UP}" != "true" ]; then
                        echo "WARNING: SonarQube is not UP yet at ${SONARQUBE_URL}. Skipping scan so deployment is not blocked."
                        exit 0
                    fi

                    TOKEN_RESP=$(curl -sf -u admin:admin -X POST "${SONARQUBE_URL}/api/user_tokens/generate?name=jenkins-build-${BUILD_NUMBER}" || true)
                    SONAR_TOKEN=$(echo "${TOKEN_RESP}" | jq -r '.token // empty')

                    if [ -z "${SONAR_TOKEN}" ]; then
                        echo "Could not auto-generate SonarQube token with default credentials; attempting anonymous/login fallback..."
                        AUTH_ARGS="/d:sonar.login=admin /d:sonar.password=admin"
                    else
                        AUTH_ARGS="/d:sonar.login=${SONAR_TOKEN}"
                    fi

                    echo "Running SonarScanner for .NET inside mcr.microsoft.com/dotnet/sdk:8.0..."
                    docker run --rm \
                        --network ci-net \
                        --volumes-from jenkins \
                        -w "${WORKSPACE}" \
                        mcr.microsoft.com/dotnet/sdk:8.0 \
                        bash -c "
                            set -e
                            apt-get update -qq && apt-get install -y -qq --no-install-recommends default-jre-headless >/dev/null
                            dotnet tool install --global dotnet-sonarscanner --version 9.0.2 >/dev/null 2>&1 || dotnet tool install --global dotnet-sonarscanner >/dev/null 2>&1
                            export PATH=\"\$PATH:/root/.dotnet/tools\"
                            rm -rf ./TestResults
                            dotnet sonarscanner begin \
                                /k:\"dotnet-app\" \
                                /n:\"dotnet-app\" \
                                /v:\"build-${BUILD_NUMBER}\" \
                                /d:sonar.host.url=\"${SONARQUBE_URL}\" \
                                /d:sonar.scanner.scanAll=false \
                                /d:sonar.cs.opencover.reportsPaths=\"**/coverage.opencover.xml\" \
                                ${AUTH_ARGS}
                            dotnet build \"${PROJECT_FILE}\" --configuration Release
                            dotnet test tests/dotnet.Tests/dotnet.Tests.csproj \
                                --configuration Release \
                                --collect:\"XPlat Code Coverage\" \
                                --results-directory ./TestResults \
                                -- DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=opencover
                            dotnet sonarscanner end ${AUTH_ARGS}
                        "
                    echo "SonarQube analysis completed. View results at SonarQube UI port 9000."
                '''
            }
        }

        stage('Build Image') {
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

                    docker build \
                        --build-arg PROJECT_FILE="${PROJECT_FILE}" \
                        --build-arg APP_DLL="${APP_DLL}" \
                        -t "${IMAGE_URI}" .
                '''
            }
        }

        stage('Trivy Image Scan') {
            steps {
                sh '''
                    set -e
                    IMAGE_URI=$(cat .image-uri)
                    echo "Running Trivy container image vulnerability scan on ${IMAGE_URI}..."
                    trivy image \
                        --severity HIGH,CRITICAL \
                        --ignore-unfixed \
                        --no-progress \
                        --exit-code 0 \
                        -o trivy-image-report.txt \
                        "${IMAGE_URI}"
                    cat trivy-image-report.txt
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-image-report.txt', allowEmptyArchive: true
                }
            }
        }

        stage('Push to ECR') {
            steps {
                sh '''
                    set -e

                    export AWS_DEFAULT_REGION="${AWS_REGION}"

                    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
                    IMAGE_URI=$(cat .image-uri)

                    aws ecr get-login-password --region "${AWS_REGION}" |
                        docker login \
                            --username AWS \
                            --password-stdin \
                            "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

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

                    IMAGE_URI=$(cat .image-uri)
                    sed -i "s|REPLACE_WITH_ECR_REPOSITORY_URL:v1|${IMAGE_URI}|g" k8s/deployment.yaml

                    kubectl apply -f k8s/serviceaccount.yaml
                    kubectl apply -f k8s/service.yaml
                    kubectl apply -f k8s/deployment.yaml

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
                rm -f trivy-fs-report.txt trivy-image-report.txt
            '''
        }
    }
}
