#!/bin/bash
# Setup kubectl locally to access EKS via Tailscale
# Run this after Tailscale subnet routes are approved and working

set -e

ENV=${ENV:-dev}
REGION=${REGION:-us-east-1}

echo "Setting up kubectl for local access via Tailscale..."

# Update kubeconfig to use EKS cluster
aws eks update-kubeconfig --name ${ENV}-eks --region ${REGION}

echo "✅ kubectl configured for ${ENV}-eks cluster"
echo ""
echo "Test connection:"
echo "  kubectl get nodes"
echo ""
echo "If connection fails, ensure:"
echo "1. Tailscale is running locally: tailscale status"
echo "2. Subnet routes are approved in Tailscale admin console"
echo "3. EKS endpoint is accessible: curl -k https://$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' | cut -d'/' -f3)"
