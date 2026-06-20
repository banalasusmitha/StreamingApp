pipeline {
  agent any

  environment {
    AWS_REGION   = "ap-south-1"
    AWS_ACCOUNT  = "123456789012"                 // <-- replace with your AWS account ID
    REGISTRY     = "${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    IMAGE_TAG    = "${env.BUILD_NUMBER}"
    // Frontend build-time API URLs (point at your ELB/Ingress host in real deploys)
    REACT_APP_AUTH_API_URL       = "http://localhost:3001/api"
    REACT_APP_STREAMING_API_URL  = "http://localhost:3002/api"
    REACT_APP_STREAMING_PUBLIC_URL = "http://localhost:3002"
    REACT_APP_ADMIN_API_URL      = "http://localhost:3003/api/admin"
    REACT_APP_CHAT_API_URL       = "http://localhost:3004/api/chat"
    REACT_APP_CHAT_SOCKET_URL    = "http://localhost:3004"
  }

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('ECR Login') {
      steps {
        sh '''
          aws ecr get-login-password --region $AWS_REGION \
            | docker login --username AWS --password-stdin $REGISTRY
        '''
      }
    }

    stage('Ensure ECR Repos') {
      steps {
        sh '''
          for repo in streamingapp-frontend streamingapp-auth streamingapp-streaming streamingapp-admin streamingapp-chat; do
            aws ecr describe-repositories --repository-names $repo --region $AWS_REGION >/dev/null 2>&1 \
              || aws ecr create-repository --repository-name $repo --region $AWS_REGION
          done
        '''
      }
    }

    stage('Build & Push - auth') {
      steps {
        sh '''
          docker build -t $REGISTRY/streamingapp-auth:$IMAGE_TAG -t $REGISTRY/streamingapp-auth:latest \
            ./backend/authService
          docker push $REGISTRY/streamingapp-auth:$IMAGE_TAG
          docker push $REGISTRY/streamingapp-auth:latest
        '''
      }
    }

    stage('Build & Push - streaming') {
      steps {
        sh '''
          docker build -t $REGISTRY/streamingapp-streaming:$IMAGE_TAG -t $REGISTRY/streamingapp-streaming:latest \
            -f ./backend/streamingService/Dockerfile ./backend
          docker push $REGISTRY/streamingapp-streaming:$IMAGE_TAG
          docker push $REGISTRY/streamingapp-streaming:latest
        '''
      }
    }

    stage('Build & Push - admin') {
      steps {
        sh '''
          docker build -t $REGISTRY/streamingapp-admin:$IMAGE_TAG -t $REGISTRY/streamingapp-admin:latest \
            -f ./backend/adminService/Dockerfile ./backend
          docker push $REGISTRY/streamingapp-admin:$IMAGE_TAG
          docker push $REGISTRY/streamingapp-admin:latest
        '''
      }
    }

    stage('Build & Push - chat') {
      steps {
        sh '''
          docker build -t $REGISTRY/streamingapp-chat:$IMAGE_TAG -t $REGISTRY/streamingapp-chat:latest \
            -f ./backend/chatService/Dockerfile ./backend
          docker push $REGISTRY/streamingapp-chat:$IMAGE_TAG
          docker push $REGISTRY/streamingapp-chat:latest
        '''
      }
    }

    stage('Build & Push - frontend') {
      steps {
        sh '''
          docker build \
            --build-arg REACT_APP_AUTH_API_URL=$REACT_APP_AUTH_API_URL \
            --build-arg REACT_APP_STREAMING_API_URL=$REACT_APP_STREAMING_API_URL \
            --build-arg REACT_APP_STREAMING_PUBLIC_URL=$REACT_APP_STREAMING_PUBLIC_URL \
            --build-arg REACT_APP_ADMIN_API_URL=$REACT_APP_ADMIN_API_URL \
            --build-arg REACT_APP_CHAT_API_URL=$REACT_APP_CHAT_API_URL \
            --build-arg REACT_APP_CHAT_SOCKET_URL=$REACT_APP_CHAT_SOCKET_URL \
            -t $REGISTRY/streamingapp-frontend:$IMAGE_TAG -t $REGISTRY/streamingapp-frontend:latest \
            ./frontend
          docker push $REGISTRY/streamingapp-frontend:$IMAGE_TAG
          docker push $REGISTRY/streamingapp-frontend:latest
        '''
      }
    }

    stage('Deploy to EKS (Helm)') {
      when { branch 'main' }
      steps {
        sh '''
          aws eks update-kubeconfig --name streamingapp --region $AWS_REGION
          helm upgrade --install streamingapp ./helm/streamingapp \
            --namespace streamingapp --create-namespace \
            --set image.registry=$REGISTRY \
            --set image.tag=$IMAGE_TAG
        '''
      }
    }
  }

  post {
    success {
      sh '''
        aws sns publish --region $AWS_REGION \
          --topic-arn arn:aws:sns:$AWS_REGION:$AWS_ACCOUNT:deployment-events \
          --subject "Jenkins build #$IMAGE_TAG SUCCESS" \
          --message "StreamingApp build $IMAGE_TAG succeeded and was pushed to ECR." || true
      '''
    }
    failure {
      sh '''
        aws sns publish --region $AWS_REGION \
          --topic-arn arn:aws:sns:$AWS_REGION:$AWS_ACCOUNT:deployment-events \
          --subject "Jenkins build #$IMAGE_TAG FAILED" \
          --message "StreamingApp build $IMAGE_TAG failed. Check Jenkins console." || true
      '''
    }
  }
}
