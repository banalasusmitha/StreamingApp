#!/usr/bin/env bash
# setup-eks.sh — create EKS cluster, enable autoscaling metrics, CloudWatch Container Insights
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
CLUSTER="${CLUSTER:-streamingapp}"

echo ">> Creating EKS cluster (10-15 min)"
eksctl create cluster \
  --name "$CLUSTER" \
  --region "$AWS_REGION" \
  --nodegroup-name workers \
  --node-type t3.medium \
  --nodes 2 --nodes-min 2 --nodes-max 4 \
  --managed

echo ">> Updating kubeconfig"
aws eks update-kubeconfig --name "$CLUSTER" --region "$AWS_REGION"

echo ">> Installing metrics-server (needed for HPA)"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo ">> Enabling CloudWatch Container Insights + Fluent Bit logging"
ClusterName="$CLUSTER"
RegionName="$AWS_REGION"
curl -s https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluent-bit-quickstart.yaml \
  | sed "s/{{cluster_name}}/$ClusterName/;s/{{region_name}}/$RegionName/" \
  | kubectl apply -f -

echo ">> EKS ready. Next: helm upgrade --install streamingapp ./helm/streamingapp -n streamingapp --create-namespace"
