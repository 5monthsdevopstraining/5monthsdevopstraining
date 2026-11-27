pipeline {
  agent any
  triggers { pollSCM('* * * * *') }
  environment {
    REGION = 'ap-south-1'
    REGISTRY = '569659729665.dkr.ecr.ap-south-1.amazonaws.com'
    REPO = 'practice-dev-ap-south-1-ecr-app'
    TRIVY_CACHE_DIR = '/var/lib/jenkins/.cache/trivy'
  }
  stages {
    stage('Build image') {
      steps {
        sh 'docker build -t $REGISTRY/$REPO:$BUILD_NUMBER dotnet'
      }
    }
   stage('Trivy Scan') {
      steps {
        sh 'trivy image --severity HIGH,CRITICAL --exit-code 0 --no-progress $REGISTRY/$REPO:$BUILD_NUMBER'
      }
    }
    stage('Push to ECR') {
      steps {
        sh '''
          aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REGISTRY
          docker push $REGISTRY/$REPO:$BUILD_NUMBER
        '''
      }
    }
    stage('Deploy') {
      steps {
        sh '''
          kubectl -n app set image deployment/app app=$REGISTRY/$REPO:$BUILD_NUMBER
          kubectl -n app rollout status deployment/app --timeout=300s
        '''
      }
    }
  }
}
