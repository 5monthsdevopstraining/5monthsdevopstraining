
pipeline {
    agent any

    triggers {
        pollSCM('* * * * *')
    }

    environment {
        REGION   = 'ap-south-1'
        REGISTRY = '569659729665.dkr.ecr.ap-south-1.amazonaws.com'
        REPO     = 'practice-dev-ap-south-1-ecr-app'
        IMAGE    = "${REGISTRY}/${REPO}:${BUILD_NUMBER}"
        TRIVY_CACHE_DIR = '/var/lib/jenkins/.cache/trivy'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build Image') {
            steps {
                sh 'docker build -t $IMAGE dotnet'
            }
        }

        stage('Trivy Scan') {
            steps {
                sh '''
                    trivy image \
                    --severity HIGH,CRITICAL \
                    --exit-code 0 \
                    --no-progress \
                    --format table \
                    -o trivy-report.txt $IMAGE

                    cat trivy-report.txt
                '''
            }

            post {
                always {
                    archiveArtifacts artifacts: 'trivy-report.txt',
                                     allowEmptyArchive: true
                }
            }
        }

        stage('Push to ECR') {
            steps {
                sh '''
                    aws ecr get-login-password --region $REGION |
                    docker login --username AWS --password-stdin $REGISTRY

                    docker push $IMAGE
                '''
            }
        }

        stage('Deploy to EKS') {
            steps {
                sh '''
                    kubectl -n app set image deployment/app app=$IMAGE

                    kubectl -n app rollout status deployment/app --timeout=300s
                '''
            }
        }
    }
}
