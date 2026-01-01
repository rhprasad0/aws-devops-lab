# Guestbook App: External Secrets Migration

## Overview

The guestbook application should be updated to read API keys from a Kubernetes Secret (injected as an environment variable) instead of calling AWS Secrets Manager directly.

This change follows the industry-standard pattern where External Secrets Operator (ESO) syncs secrets from AWS Secrets Manager to Kubernetes Secrets, and applications consume them via standard K8s mechanisms.

## Required Code Changes

### Before (Direct SDK Call)

```python
import boto3
import json
import os

# Fetch secret name from environment
secret_name = os.environ["API_KEYS_SECRET_NAME"]

# Call AWS Secrets Manager API
client = boto3.client("secretsmanager")
response = client.get_secret_value(SecretId=secret_name)

# Parse the secret
secret_data = json.loads(response["SecretString"])
api_keys = secret_data["api_keys"]
```

### After (K8s-Native)

```python
import json
import os

# Read directly from environment variable (injected from K8s Secret)
api_keys = json.loads(os.environ["API_KEYS"])
```

## Environment Variable Format

The `API_KEYS` environment variable contains a JSON array:

```json
["dev-key-change-me","test-key-change-me"]
```

## Architecture

```
AWS Secrets Manager          ESO Controller         K8s Secret           Pod
(a2a-guestbook/api-keys) --> (external-secrets) --> (guestbook-api-keys) --> (API_KEYS env var)
```

## Benefits

| Aspect | Before (SDK) | After (ESO) |
|--------|--------------|-------------|
| AWS SDK dependency | Required for secrets | Not needed for secrets |
| IAM permissions | App needs `secretsmanager:GetSecretValue` | Only ESO needs IAM |
| Startup latency | API call on each start | Secret already available |
| Local testing | Needs AWS credentials | Can mock K8s Secret |
| Secret refresh | App must re-fetch | ESO polls automatically (1h) |

## Optional Cleanup

After migrating, you can optionally:

1. Remove `boto3` Secrets Manager code (keep it for DynamoDB)
2. Remove `API_KEYS_SECRET_NAME` environment variable usage
3. Remove `secretsmanager:GetSecretValue` from the guestbook IAM policy (in `infra/guestbook-iam.tf`)

## Testing

1. Deploy the updated app
2. Verify the pod has the `API_KEYS` environment variable:
   ```bash
   kubectl exec -n guestbook deploy/guestbook -- printenv API_KEYS
   ```
3. Confirm API key validation still works

## Related Files

- `k8s/guestbook/external-secret.yaml` - ExternalSecret that syncs from Secrets Manager
- `k8s/guestbook/rollout.yaml` - Injects `API_KEYS` env var from K8s Secret
- `infra/external-secrets.tf` - ESO Helm release and IAM configuration
