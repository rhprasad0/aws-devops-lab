# Security Guidelines

## Preventing Credential Exposure

### Git Pre-Commit Hook
A pre-commit hook is installed at `.git/hooks/pre-commit` that blocks commits containing:
- Sensitive file patterns (`*.auto.tfvars`, `*.pem`, `.env`, etc.)
- API keys, passwords, and AWS credentials in file content

### What to Do If Keys Are Exposed

1. **Rotate immediately:**
   ```bash
   ./scripts/rotate-api-keys.sh
   ```

2. **Update Secrets Manager:**
   ```bash
   cd infra
   terraform apply  # Updates AWS Secrets Manager with new keys
   ```

3. **Remove from Git history** (if already pushed):
   ```bash
   # Use BFG Repo-Cleaner or git-filter-repo
   git filter-repo --path infra/guestbook.auto.tfvars --invert-paths
   git push --force
   ```

4. **Notify team** if this is a shared repository

### Best Practices

1. **Never commit `.auto.tfvars` files** - Use `.example` templates instead
2. **Use AWS Secrets Manager** for all sensitive data
3. **Generate strong keys:** `openssl rand -hex 32`
4. **Rotate keys regularly** (every 90 days minimum)
5. **Enable GitHub secret scanning** for public repos
6. **Use IRSA** for pod-level AWS access instead of embedding credentials

### File Patterns to Never Commit
- `*.auto.tfvars`
- `terraform.tfvars`
- `.env` (use `.env.example`)
- `*.pem`, `*.key`
- Any file with `secret` or `password` in the name

### Verification
Test the pre-commit hook:
```bash
# This should be blocked
echo 'api_key = "abc123"' > test.auto.tfvars
git add test.auto.tfvars
git commit -m "test"  # Should fail
```
