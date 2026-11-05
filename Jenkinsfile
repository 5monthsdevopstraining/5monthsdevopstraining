// Builds ./app (.NET API) and deploys it to Public 1 (port 80) and the private EC2 (port 8080) on every push to main.
// Jenkins runs inside the VPC, so it reaches both servers on their private IPs.

pipeline {
  agent any

  triggers {
    githubPush()            // instant, if a GitHub webhook is configured (needs repo admin)
    pollSCM('H/2 * * * *')  // fallback: check the branch for new commits every ~2 minutes
  }

  environment {
    // Private IPs are pinned in Terraform, so they stay the same when EC2s are recreated
    PUBLIC_HOST  = '10.0.1.10' // fixed in terraform/main.tf
    PRIVATE_HOST = '10.0.3.10' // fixed in terraform/main.tf
    APP_NAME     = 'sample-app'
    AWS_REGION   = 'ap-south-1'
  }

  options {
    disableConcurrentBuilds()
    timeout(time: 20, unit: 'MINUTES')
  }

  stages {
    stage('Deploy') {
      parallel {
        stage('Public EC2') {
          steps { deployTo(env.PUBLIC_HOST, 80) }
        }
        stage('Private EC2') {
          steps { deployTo(env.PRIVATE_HOST, 8080) }
        }
      }
    }

    stage('Health check') {
      steps {
        sh '''
          curl -fsS --retry 10 --retry-delay 3 --retry-all-errors http://$PUBLIC_HOST/swagger/index.html      > /dev/null
          curl -fsS --retry 10 --retry-delay 3 --retry-all-errors http://$PRIVATE_HOST:8080/swagger/index.html > /dev/null
          echo "Both servers are serving the app"
        '''
      }
    }
  }
}

// Copies ./app to the server, builds it there with Docker and (re)starts the container.
def deployTo(String host, int port) {
  withCredentials([sshUserPrivateKey(credentialsId: 'ec2-ssh-key', keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER')]) {
    withEnv(["HOST=${host}", "PORT=${port}"]) {
      sh '''
        # EC2s get new host keys when recreated, so don't pin them
        SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15"

        # Install Docker on first deploy, and add swap so the .NET build fits in 1 GB RAM (t3.micro)
        ssh $SSH_OPTS $SSH_USER@$HOST '
          if ! command -v docker >/dev/null; then
            until sudo dnf install -y docker; do sleep 10; done
          fi
          sudo systemctl enable --now docker
          if [ ! -f /swapfile ]; then
            sudo dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
            sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
            echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab
          fi
          rm -rf /tmp/app && mkdir -p /tmp/app
        '

        scp $SSH_OPTS -r app/. $SSH_USER@$HOST:/tmp/app/

        ssh $SSH_OPTS $SSH_USER@$HOST "
          set -e
          sudo docker build -t $APP_NAME:$BUILD_NUMBER -t $APP_NAME:latest /tmp/app
          sudo docker rm -f $APP_NAME 2>/dev/null || true
          sudo docker run -d --name $APP_NAME --restart unless-stopped -p $PORT:8080 \
            -e AWS__Region=$AWS_REGION $APP_NAME:latest
          sudo docker image prune -f
          sudo docker builder prune -f
        "
      '''
    }
  }
}
