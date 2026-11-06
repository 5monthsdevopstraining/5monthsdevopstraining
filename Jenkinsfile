
pipeline {
    agent any

    triggers {
        pollSCM('H/2 * * * *')
    }

    environment {
        APP_SERVER = 'ec2-user@10.0.2.153'
        DEPLOY_DIR = '/var/www/myapp'
        APP_PORT = '3000'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                sh 'git branch --show-current'
            }
        }

        stage('Build') {
            steps {
                sh 'dotnet --version'
                sh 'dotnet restore'
                sh 'dotnet build -c Release --no-restore'
            }
        }

        stage('Publish') {
            steps {
                sh '''
                    rm -rf publish_output app.tar.gz
                    dotnet publish -c Release --no-build -o publish_output
                    tar -czf app.tar.gz -C publish_output .
                '''
            }
        }

        stage('Deploy') {
            when {
                branch 'Jebin-Icanio'
            }

            steps {
                sshagent(credentials: ['app-server-ssh']) {
                    sh """
                        scp -o StrictHostKeyChecking=no app.tar.gz ${APP_SERVER}:/tmp/app.tar.gz

                        ssh -o StrictHostKeyChecking=no ${APP_SERVER} '
                            sudo mkdir -p ${DEPLOY_DIR}
                            sudo find ${DEPLOY_DIR} -mindepth 1 -delete
                            sudo tar -xzf /tmp/app.tar.gz -C ${DEPLOY_DIR}
                            sudo systemctl restart myapp
                            sleep 5
                            curl -f http://localhost:${APP_PORT} || (
                                sudo journalctl -u myapp -n 30 --no-pager
                                exit 1
                            )
                        '
                    """
                }
            }
        }
    }

    post {
        success {
            echo 'Pipeline completed successfully'
        }

        failure {
            echo 'Pipeline failed. Check the console output.'
        }
    }
}
