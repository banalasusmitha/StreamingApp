#!/usr/bin/env bash
# setup-sns-chatops.sh — create SNS topic for deployment events (Bonus Step 9)
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
TOPIC_NAME="deployment-events"

echo ">> Creating SNS topic"
TOPIC_ARN=$(aws sns create-topic --name "$TOPIC_NAME" --region "$AWS_REGION" --query TopicArn --output text)
echo "Topic ARN: $TOPIC_ARN"

# Option A: email subscription (simplest proof)
if [ -n "${ALERT_EMAIL:-}" ]; then
  aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email \
    --notification-endpoint "$ALERT_EMAIL" --region "$AWS_REGION"
  echo ">> Confirm the subscription via the email you just received."
fi

# Option B: Slack via AWS Chatbot — configure in console:
#   AWS Chatbot > Configure new client > Slack > pick channel > subscribe to this SNS topic.
# Option C: Lambda subscriber that POSTs to a Slack/Teams/Telegram incoming webhook.

echo ">> Test publish:"
aws sns publish --topic-arn "$TOPIC_ARN" --region "$AWS_REGION" \
  --subject "ChatOps test" --message "SNS topic wired for StreamingApp deployment events."

echo ">> Use this ARN in the Jenkinsfile post{} block: $TOPIC_ARN"
