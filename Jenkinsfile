pipeline {
    agent any

    triggers {
        pollSCM('H/2 * * * *')
    }

    environment {
        APP_SERVER = 'ec2-user@10.0.2.153'
        DEPLOY_DIR = '/var/www/myapp'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            steps {
                sh 'dotnet restore'
                sh 'dotnet build -c Release --no-restore'
            }
        }

        stage('Publish') {
            steps {
                sh 'rm -rf publish_output app.tar.gz'
                sh 'dotnet publish -c Release -o publish_output'
                sh 'tar -czf app.tar.gz -C publish_output .'
            }
        }

        stage('Deploy') {
            steps {
                sshagent(credentials: ['app-server-ssh']) {
                    sh """
                        scp -o StrictHostKeyChecking=no app.tar.gz ${APP_SERVER}:/tmp/app.tar.gz
                        ssh -o StrictHostKeyChecking=no ${APP_SERVER} '
                            rm -rf ${DEPLOY_DIR}/*
                            tar -xzf /tmp/app.tar.gz -C ${DEPLOY_DIR}
                            sudo systemctl restart myapp
                            sleep 5
                            curl -f http://localhost:3000 || (sudo journalctl -u myapp -n 30 --no-pager; exit 1)
                        '
                    """
                }
            }
        }
    }

    post {
        success { echo 'Deployed successfully' }
        failure { echo 'Deployment failed, check the console output' }
    }
}
