#!/usr/bin/env bash
# build-and-push.sh — build all 5 images and push to ECR
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
AWS_ACCOUNT="${AWS_ACCOUNT:?set AWS_ACCOUNT to your 12-digit account id}"
REGISTRY="${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"
TAG="${TAG:-latest}"

REPOS=(streamingapp-frontend streamingapp-auth streamingapp-streaming streamingapp-admin streamingapp-chat)

echo ">> Logging in to ECR"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

echo ">> Ensuring repositories exist"
for r in "${REPOS[@]}"; do
  aws ecr describe-repositories --repository-names "$r" --region "$AWS_REGION" >/dev/null 2>&1 \
    || aws ecr create-repository --repository-name "$r" --region "$AWS_REGION" >/dev/null
done

echo ">> auth"
docker build -t "$REGISTRY/streamingapp-auth:$TAG" ./backend/authService
docker push "$REGISTRY/streamingapp-auth:$TAG"

echo ">> streaming (context=./backend)"
docker build -t "$REGISTRY/streamingapp-streaming:$TAG" -f ./backend/streamingService/Dockerfile ./backend
docker push "$REGISTRY/streamingapp-streaming:$TAG"

echo ">> admin (context=./backend)"
docker build -t "$REGISTRY/streamingapp-admin:$TAG" -f ./backend/adminService/Dockerfile ./backend
docker push "$REGISTRY/streamingapp-admin:$TAG"

echo ">> chat (context=./backend)"
docker build -t "$REGISTRY/streamingapp-chat:$TAG" -f ./backend/chatService/Dockerfile ./backend
docker push "$REGISTRY/streamingapp-chat:$TAG"

echo ">> frontend"
docker build \
  --build-arg REACT_APP_AUTH_API_URL="${REACT_APP_AUTH_API_URL:-http://localhost:3001/api}" \
  --build-arg REACT_APP_STREAMING_API_URL="${REACT_APP_STREAMING_API_URL:-http://localhost:3002/api}" \
  --build-arg REACT_APP_STREAMING_PUBLIC_URL="${REACT_APP_STREAMING_PUBLIC_URL:-http://localhost:3002}" \
  --build-arg REACT_APP_ADMIN_API_URL="${REACT_APP_ADMIN_API_URL:-http://localhost:3003/api/admin}" \
  --build-arg REACT_APP_CHAT_API_URL="${REACT_APP_CHAT_API_URL:-http://localhost:3004/api/chat}" \
  --build-arg REACT_APP_CHAT_SOCKET_URL="${REACT_APP_CHAT_SOCKET_URL:-http://localhost:3004}" \
  -t "$REGISTRY/streamingapp-frontend:$TAG" ./frontend
docker push "$REGISTRY/streamingapp-frontend:$TAG"

echo ">> Done. Images pushed with tag '$TAG'."
