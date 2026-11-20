pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()                       // one deploy at a time
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 30, unit: 'MINUTES')
    }

    // Check GitHub every 5 minutes; build only when there are new commits.
    // "H" spreads the exact minute to avoid load spikes. No webhooks used.
    triggers {
        pollSCM('H/5 * * * *')
    }

    environment {
        AWS_REGION    = 'ap-southeast-2'
        CLUSTER_NAME  = 'eks-dev-week-10-region-1-01'
        K8S_NAMESPACE = 'dotnet-app'
        RELEASE_NAME  = 'dotnet-app'
        CHART_PATH    = 'helm/dotnet-app'
        IMAGE_REPO    = 'srinithi25/devops-week11-task'
    }

    stages {

        stage('SCM Polling') {
            steps {
                script {
                    def causes = currentBuild.getBuildCauses().collect { it.shortDescription }.join(', ')
                    echo "Build triggered by: ${causes}"
                    echo "Polling schedule: H/5 * * * * on branch srinithi-icanio (no webhooks)"
                }
            }
        }

        stage('Checkout') {
            steps {
                checkout scm
                script {
                    def shortSha = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    // Unique, traceable tag: <build number>-<commit>  e.g. 7-a1b2c3d
                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${shortSha}"
                    env.KUBECONFIG = "${env.WORKSPACE}/.kube/config"   // per-job kubeconfig
                }
                echo "Image to build: ${IMAGE_REPO}:${IMAGE_TAG}"
            }
        }

        stage('Docker Build') {
            steps {
                sh '''
                    docker build \
                      --label org.opencontainers.image.revision="$(git rev-parse HEAD)" \
                      --label jenkins.build="${BUILD_NUMBER}" \
                      -t "${IMAGE_REPO}:${IMAGE_TAG}" .
                    docker image ls "${IMAGE_REPO}:${IMAGE_TAG}"
                '''
            }
        }

        stage('Docker Hub Authentication') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                                  usernameVariable: 'DOCKERHUB_USER',
                                                  passwordVariable: 'DOCKERHUB_TOKEN')]) {
                    // Single quotes: the token is expanded by the shell, never by Groovy,
                    // and --password-stdin keeps it out of the process list.
                    sh 'echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin'
                }
            }
        }

        stage('Docker Image Push') {
            steps {
                sh 'docker push "${IMAGE_REPO}:${IMAGE_TAG}"'
            }
        }

        stage('Configure EKS Access') {
            steps {
                // Credentials come from the EC2 instance role - no access keys stored.
                sh '''
                    aws sts get-caller-identity --query Arn --output text
                    mkdir -p "$(dirname "$KUBECONFIG")"
                    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" --kubeconfig "$KUBECONFIG"
                    kubectl auth can-i create deployments -n "$K8S_NAMESPACE"
                    kubectl get pods -n "$K8S_NAMESPACE"
                '''
            }
        }

        stage('Helm Upgrade/Install') {
            steps {
                // --atomic: if pods never become healthy, Helm rolls back automatically.
                sh '''
                    helm lint "$CHART_PATH"
                    helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
                      --namespace "$K8S_NAMESPACE" \
                      --set image.tag="$IMAGE_TAG" \
                      --wait --atomic --timeout 10m \
                      --history-max 10
                '''
            }
        }

        stage('Deployment Rollout Verification') {
            steps {
                sh '''
                    kubectl rollout status deployment/"$RELEASE_NAME" -n "$K8S_NAMESPACE" --timeout=5m

                    RUNNING_IMAGE=$(kubectl get deployment "$RELEASE_NAME" -n "$K8S_NAMESPACE" \
                      -o jsonpath='{.spec.template.spec.containers[0].image}')
                    echo "Running image : $RUNNING_IMAGE"
                    echo "Expected image: ${IMAGE_REPO}:${IMAGE_TAG}"
                    [ "$RUNNING_IMAGE" = "${IMAGE_REPO}:${IMAGE_TAG}" ] || { echo "Image mismatch"; exit 1; }
                '''
            }
        }

        stage('Deployment Status') {
            steps {
                sh '''
                    helm status "$RELEASE_NAME" -n "$K8S_NAMESPACE"
                    helm history "$RELEASE_NAME" -n "$K8S_NAMESPACE" --max 5
                    kubectl get pods,svc,ingress -n "$K8S_NAMESPACE" -o wide

                    ALB_DNS=$(kubectl get ingress "$RELEASE_NAME" -n "$K8S_NAMESPACE" \
                      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
                    echo "Application URL: http://$ALB_DNS/swagger/index.html"

                    # End-to-end check through the public ALB
                    for i in $(seq 1 12); do
                      CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$ALB_DNS/health" || true)
                      echo "Attempt $i: /health -> $CODE"
                      [ "$CODE" = "200" ] && exit 0
                      sleep 10
                    done
                    echo "ALB health check did not return 200"; exit 1
                '''
            }
        }
    }

    post {
        always {
            // Remove Docker Hub login and the local image (keeps the disk clean)
            sh '''
                docker logout || true
                docker image rm "${IMAGE_REPO}:${IMAGE_TAG}" || true
            '''
        }
        success {
            echo "Deployed ${IMAGE_REPO}:${IMAGE_TAG} to ${CLUSTER_NAME}/${K8S_NAMESPACE}"
        }
        failure {
            echo "Pipeline failed - check the stage logs above. Helm --atomic rolled back any failed release."
        }
    }
}
