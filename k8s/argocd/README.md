# ArgoCD Bootstrap Pattern

This directory implements the "App of Apps" pattern for GitOps.

## Structure

```
k8s/argocd/
├── projects/              # AppProject definitions (governance)
│   └── guestbook-project.yaml
├── applications/          # Application definitions (deployments)
│   └── guestbook.yaml
└── values.yaml           # ArgoCD Helm values
```

## How It Works

1. **Terraform** installs ArgoCD and creates the bootstrap Application (`argocd-apps`)
2. **Bootstrap Application** watches this directory and syncs all YAML files
3. **Projects** define security boundaries (allowed repos, namespaces, resources)
4. **Applications** define what to deploy and where

## Adding New Apps

1. Create AppProject in `projects/` (optional, can reuse existing)
2. Create Application in `applications/`
3. Commit and push - ArgoCD auto-syncs within 3 minutes

No `terraform apply` needed!
