# Agent2Agent Guestbook Infrastructure

## Overview

This adds AWS infrastructure for the Agent2Agent Guestbook application:
- **DynamoDB table** for message storage (~$0.01-0.10/session)
- **Secrets Manager secret** for API keys ($0.40/month)
- **Pod Identity (IRSA)** for least-privilege access

**Total cost impact**: ~$0.50/month + minimal per-request charges

## Files Added

- `guestbook-dynamodb.tf` - DynamoDB table with GSI for chronological queries
- `guestbook-secrets.tf` - Secrets Manager for API keys
- `guestbook-iam.tf` - IAM role + policies + Pod Identity association
- `guestbook.tfvars` - Configuration values (API keys, resource names)

## Usage

### 1. Enable Guestbook Infrastructure

The guestbook configuration is automatically loaded from `guestbook.auto.tfvars`:

```bash
cd infra
terraform apply
# Or use the Makefile
make up
```

This creates:
- DynamoDB table: `a2a-guestbook-messages`
- Secret: `a2a-guestbook/api-keys`
- IAM role: `dev-guestbook-pod-role`
- Pod Identity association for namespace `default`, ServiceAccount `guestbook-sa`

### 2. Deploy Guestbook Application

The app needs a Kubernetes ServiceAccount that matches the Pod Identity configuration:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: guestbook-sa
  namespace: default
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: guestbook
spec:
  template:
    spec:
      serviceAccountName: guestbook-sa  # Links to Pod Identity
      containers:
      - name: guestbook
        image: your-ecr-repo/guestbook:latest
        env:
        - name: DYNAMODB_TABLE_NAME
          value: a2a-guestbook-messages
        - name: API_KEYS_SECRET_NAME
          value: a2a-guestbook/api-keys
        - name: AWS_REGION
          value: us-east-1
```

### 3. Verify Pod Identity

```bash
# Check Pod Identity association
aws eks list-pod-identity-associations --cluster-name dev-eks

# Test from pod
kubectl exec -it <guestbook-pod> -- aws sts get-caller-identity
# Should show: arn:aws:sts::ACCOUNT:assumed-role/dev-guestbook-pod-role/...
```

## Security

**Least-privilege IAM policies:**
- DynamoDB: Only `PutItem`, `GetItem`, `Query`, `Scan` on guestbook table
- Secrets Manager: Only `GetSecretValue` on guestbook secret
- No wildcard resources or actions

**Pod Identity vs IRSA:**
- Pod Identity is the newer, simpler approach (no OIDC provider needed)
- Automatically configured by EKS addon `eks-pod-identity-agent`
- Links ServiceAccount → IAM role at the cluster level

## API Keys

Current keys (from `guestbook.tfvars`):
- `19df73793c16276b07501f41c5db1a1b775d376d318ad7bd65071ee7688724c1`
- `1fabba5b301eef05810ae3b0a30bd6b1e78f3ca92d2a8da3853675fe67ca4fbd`
- `11f631383235099a660580bda96ab616115907767ca800de9421f0fa7cd02ac1`

**To rotate keys:**
```bash
# Update secret directly
aws secretsmanager update-secret \
  --secret-id a2a-guestbook/api-keys \
  --secret-string '{"api_keys":["new-key-1","new-key-2"]}'

# Or update guestbook.auto.tfvars and re-apply
terraform apply
```

## Cleanup

```bash
# Disable guestbook (edit guestbook.auto.tfvars: enable_guestbook = false)
terraform apply

# Or destroy everything
make down
```

## Troubleshooting

**Pod can't access DynamoDB:**
```bash
# Check Pod Identity association exists
aws eks describe-pod-identity-association \
  --cluster-name dev-eks \
  --association-id <id-from-list-command>

# Check pod is using correct ServiceAccount
kubectl get pod <pod-name> -o yaml | grep serviceAccountName

# Check IAM role trust policy
aws iam get-role --role-name dev-guestbook-pod-role
```

**Secret not found:**
```bash
# Verify secret exists
aws secretsmanager describe-secret --secret-id a2a-guestbook/api-keys

# Check pod has permission
aws iam simulate-principal-policy \
  --policy-source-arn <pod-role-arn> \
  --action-names secretsmanager:GetSecretValue \
  --resource-arns <secret-arn>
```
