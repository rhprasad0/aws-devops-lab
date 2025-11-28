# AGENTS.md

Guidelines for coding agents working in this repository.

**Context:** Production-style EKS learning lab | **Budget:** $250/month | **Current:** Week 10+ (Weeks 0-9 complete)

---

## Core Principles

1. **Explain WHY** - Justify design choices; assume the user is learning
2. **Everything as Code** - Terraform for infra, Helm/manifests for K8s, no console changes
3. **Ephemeral by Default** - Easy create/destroy, no mystery resources or surprise bills
4. **Prod-Parity, Dev-Scale** - Same tools as production, minimal sizes
5. **Cost-Aware** - Always estimate costs, warn about persistent resources

---

## Quick Reference

### Tagging (Required)
```hcl
default_tags {
  tags = {
    project    = "eks-ephemeral-lab"
    env        = var.env
    owner      = var.owner
    created_at = timestamp()
    ttl_hours  = var.ttl_hours
  }
}
```

### Cost Limits
- **Hard limit:** No resource >$5/day without explicit approval
- **Avoid:** NAT Gateways ($32/mo), Shield Advanced, large RDS/OpenSearch
- **Prefer:** t3.small/t4g.small nodes, 20GB gp3, short retention periods

### Security Defaults
- IRSA over node IAM for pod access
- Least-privilege IAM policies
- HTTPS for public endpoints
- Secrets Manager + External Secrets Operator for credentials
- No plaintext secrets in manifests

---

## Interaction Pattern

1. **Identify week** - Ask if unclear: "Which week are you working on?"
2. **Check prerequisites** - Ensure prior weeks are complete
3. **Estimate cost/time** - Include in proposals
4. **Propose minimal changes** - One component at a time
5. **Explain** - WHY, not just WHAT; include debugging tips
6. **Include verification** - Testing commands and cleanup steps

**Buffer weeks (7, 13):** Suggest refactoring, documentation, cost review - don't push ahead.

---

## Forbidden Actions

- Silently create expensive resources
- Remove `make down` or break ephemerality
- Auto-run destructive commands (`terraform destroy`, etc.)
- Generate large opaque modules without explanation
- Skip ahead of current week without approval

---

## MCP Tools Available

### awslabs.terraform-mcp-server
Terraform/Terragrunt execution, Checkov security scans, AWS provider documentation
- `ExecuteTerraformCommand`, `ExecuteTerragruntCommand`, `RunCheckovScan`
- `SearchAwsProviderDocs`, `SearchAwsccProviderDocs`, `SearchSpecificAwsIaModules`, `SearchUserProvidedModule`

### awslabs.core-mcp-server
AWS knowledge, documentation, and CLI operations
- `prompt_understanding` - Translate queries to AWS expert advice
- `aws_knowledge_aws___*` - Regional availability, documentation search/read, recommendations
- `aws_api_call_aws` - Execute AWS CLI commands
- `aws_api_suggest_aws_commands` - Get CLI command suggestions

### awslabs.eks-mcp-server
EKS cluster and Kubernetes resource management
- `manage_eks_stacks` - CloudFormation-based EKS lifecycle
- `list_k8s_resources`, `manage_k8s_resource`, `apply_yaml` - K8s CRUD
- `get_pod_logs`, `get_k8s_events` - Debugging
- `get_cloudwatch_logs`, `get_cloudwatch_metrics`, `get_eks_metrics_guidance` - Observability
- `get_eks_vpc_config`, `get_eks_insights`, `search_eks_troubleshoot_guide` - Troubleshooting
- `add_inline_policy`, `get_policies_for_role` - IAM management
- `generate_app_manifest`, `list_api_versions` - Helpers

---

## Repository Structure

```
infra/           # Terraform (vpc.tf, eks.tf, iam.tf, etc.)
k8s/             # Helm/manifests (argocd/, guestbook/, etc.)
scripts/         # up.sh, down.sh, helpers
dashboards/      # Grafana dashboard JSON
docs/            # Week-specific documentation
Makefile         # make up / make down
```

---

**Remember:** Explain deeply, respect the timeline, prioritize understanding over speed.
