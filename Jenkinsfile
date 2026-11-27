pipeline {
  agent any
  triggers { pollSCM('* * * * *') }
  environment {
    REGION   = 'ap-south-1'
    REGISTRY = '569659729665.dkr.ecr.ap-south-1.amazonaws.com'
    REPO     = 'practice-dev-ap-south-1-ecr-app'
    IMAGE    = "${REGISTRY}/${REPO}:${BUILD_NUMBER}"
    TRIVY_CACHE_DIR = '/var/lib/jenkins/.cache/trivy'
  }
  stages {
    stage('Checkout') {
      steps { checkout scm }
    }
    stage('SonarQube Scan') {
      steps {
        withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
          sh '''
            docker run --rm -e SONAR_TOKEN=$SONAR_TOKEN \
              -v "$PWD/dotnet:/usr/src" \
              sonarsource/sonar-scanner-cli \
              -Dsonar.host.url=https://sonarcloud.io \
              -Dsonar.organization=<ORG_KEY> \
              -Dsonar.projectKey=<PROJECT_KEY> \
              -Dsonar.sources=. \
              -Dsonar.exclusions=bin/**,obj/**
          '''
        }
      }
    }
    stage('Build Image') {
      steps { sh 'docker build -t $IMAGE dotnet' }
    }
    stage('Trivy Scan') {
      steps {
        sh 'trivy image --severity HIGH,CRITICAL --exit-code 0 --no-progress --format table -o trivy-report.txt $IMAGE'
        sh 'cat trivy-report.txt'
      }
      post {
        always { archiveArtifacts artifacts: 'trivy-report.txt', allowEmptyArchive: true }
      }
    }
    stage('Push to ECR') {
      steps {
        sh '''
          aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REGISTRY
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
