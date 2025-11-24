#!/bin/bash
# Rotate API keys after exposure

set -e

echo "🔄 Generating new API keys..."
echo ""
echo "Add these to your guestbook.auto.tfvars:"
echo ""
echo "guestbook_initial_api_keys = ["

for i in {1..3}; do
  KEY=$(openssl rand -hex 32)
  echo "  \"$KEY\","
done

echo "]"
echo ""
echo "Then run:"
echo "  cd infra && terraform apply"
echo ""
echo "⚠️  Old keys will be invalidated after apply"
