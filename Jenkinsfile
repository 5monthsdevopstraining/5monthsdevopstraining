pipeline {
    agent any

    triggers {
        pollSCM('* * * * *')
    }

    options {
        skipDefaultCheckout(true)
    }

    environment {
        AWS_DEFAULT_REGION = 'ap-southeast-2'
    }

    stages {
        stage('Checkout SCM') {
            steps {
                checkout scm
            }
        }

        stage('Build and Push Image') {
            steps {
                sh '''
                    set -eu
                    . /etc/eks-env
                    : "${ECR_REPOSITORY_URI:?ECR_REPOSITORY_URI is missing from /etc/eks-env}"

                    aws ecr get-login-password --region "$AWS_REGION" \
                      | docker login --username AWS --password-stdin "${ECR_REPOSITORY_URI%%/*}"

                    docker build \
                      -t "$ECR_REPOSITORY_URI:$BUILD_NUMBER" \
                      -t "$ECR_REPOSITORY_URI:latest" \
                      ./app
                    docker push "$ECR_REPOSITORY_URI:$BUILD_NUMBER"
                    docker push "$ECR_REPOSITORY_URI:latest"
                '''
            }
        }

        stage('Deploy to Private EKS') {
            steps {
                sh '''
                    set -eu
                    . /etc/eks-env
                    aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

                    export IMAGE_URI="$ECR_REPOSITORY_URI:$BUILD_NUMBER"
                    envsubst '$IMAGE_URI $ALB_SG_ID $ALB_NAME $APP_PORT $HEALTH_CHECK_PATH $AWS_REGION $S3_BUCKET_NAME $RDS_HOST $RDS_DB $RDS_USER $RDS_PASSWORD' \
                      < deploy/app.yaml \
                      | kubectl apply -f -

                    kubectl rollout status deployment/app --timeout=180s
                    kubectl get pods -l app=app -o wide
                    kubectl get ingress app
                '''
            }
        }
    }
}
