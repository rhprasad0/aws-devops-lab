# =============================================================================
# Week 13: External Secrets Operator (ESO)
# =============================================================================
#
# ESO syncs secrets from external providers (AWS Secrets Manager, SSM, etc.)
# into Kubernetes Secrets. This eliminates the need for applications to call
# AWS APIs directly and keeps secrets out of Git.
#
# WHY External Secrets Operator?
# - Secrets stay in AWS Secrets Manager (single source of truth)
# - K8s Secrets auto-update when source changes (polling)
# - No plaintext secrets in manifests or environment variables at deploy time
# - Works with any K8s workload (Deployments, Rollouts, Jobs, etc.)
# - Supports secret rotation without pod restarts (refreshInterval)
#
# ARCHITECTURE:
#   AWS Secrets Manager --> ESO Controller --> K8s Secret --> Pod
#                              |
#                    ClusterSecretStore (auth config)
#
# COST IMPACT:
# - ESO itself: Negligible (~50m CPU, 128Mi memory)
# - Secrets Manager API calls: $0.05 per 10,000 calls
# - With 1-minute refresh on 5 secrets: ~$0.22/month
# =============================================================================

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "enable_external_secrets" {
  description = "Enable External Secrets Operator"
  type        = bool
  default     = true
}

variable "external_secrets_version" {
  description = "External Secrets Operator Helm chart version"
  type        = string
  default     = "0.12.1" # Latest stable as of Dec 2024
}

variable "external_secrets_namespace" {
  description = "Kubernetes namespace for External Secrets Operator"
  type        = string
  default     = "external-secrets"
}

# -----------------------------------------------------------------------------
# Namespace
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  depends_on = [module.eks.aws_eks_cluster]

  metadata {
    name = var.external_secrets_namespace
    labels = {
      name                         = "external-secrets"
      "app.kubernetes.io/name"     = "external-secrets"
      "app.kubernetes.io/instance" = "external-secrets"
      # Exempt from Kyverno policies (system component)
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

# -----------------------------------------------------------------------------
# IAM Role for External Secrets (Pod Identity)
# -----------------------------------------------------------------------------
# Uses EKS Pod Identity (successor to IRSA) for least-privilege access.
# ESO needs to read secrets from Secrets Manager to sync them to K8s.

resource "aws_iam_role" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  name = "${var.env}-external-secrets-role"

  # Trust policy for EKS Pod Identity
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = {
    Name      = "${var.env}-external-secrets-role"
    Component = "external-secrets"
  }
}

# IAM Policy for Secrets Manager access
# Scoped to secrets with specific prefix for security
resource "aws_iam_policy" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  name        = "${var.env}-external-secrets-policy"
  description = "Allow External Secrets Operator to read secrets from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GetSecretValue"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        # Scope to secrets in this account with specific prefixes
        # Adjust the resource pattern based on your naming convention
        Resource = [
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:a2a-guestbook/*",
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.env}/*"
        ]
      },
      {
        Sid    = "ListSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name      = "${var.env}-external-secrets-policy"
    Component = "external-secrets"
  }
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  role       = aws_iam_role.external_secrets[0].name
  policy_arn = aws_iam_policy.external_secrets[0].arn
}

# EKS Pod Identity Association
# Links the ESO ServiceAccount to the IAM role
resource "aws_eks_pod_identity_association" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  cluster_name    = module.eks.cluster_name
  namespace       = var.external_secrets_namespace
  service_account = "external-secrets" # Default SA name from Helm chart
  role_arn        = aws_iam_role.external_secrets[0].arn

  tags = {
    Name      = "${var.env}-external-secrets-pod-identity"
    Component = "external-secrets"
  }

  depends_on = [
    kubernetes_namespace.external_secrets,
    helm_release.external_secrets
  ]
}

# -----------------------------------------------------------------------------
# External Secrets Operator Helm Release
# -----------------------------------------------------------------------------

resource "helm_release" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  depends_on = [
    module.eks.aws_eks_cluster,
    kubernetes_namespace.external_secrets,
    module.eks
  ]

  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.external_secrets_version
  namespace  = kubernetes_namespace.external_secrets[0].metadata[0].name

  # Wait for ESO to be fully ready (CRDs + webhook)
  wait          = true
  wait_for_jobs = true
  timeout       = 600 # 10 minutes

  values = [
    yamlencode({
      # Install CRDs with the chart
      installCRDs = true

      # Controller configuration
      resources = {
        requests = {
          cpu    = "50m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
      }

      # Webhook configuration (validates ExternalSecret resources)
      webhook = {
        resources = {
          requests = {
            cpu    = "25m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }

      # Cert controller (manages webhook certificates)
      certController = {
        resources = {
          requests = {
            cpu    = "25m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }

      # ServiceAccount configuration
      serviceAccount = {
        create = true
        name   = "external-secrets"
        annotations = {
          # Note: Pod Identity doesn't require SA annotations like IRSA did
          # The association is created via aws_eks_pod_identity_association
        }
      }
    })
  ]
}

# -----------------------------------------------------------------------------
# ClusterSecretStore - AWS Secrets Manager
# -----------------------------------------------------------------------------
# NOTE: ClusterSecretStore is defined in k8s/external-secrets/cluster-secret-store.yaml
# and managed by ArgoCD. This avoids the chicken-and-egg problem where Terraform
# tries to validate the CRD before the Helm chart installs it.
#
# The ClusterSecretStore allows any namespace to create ExternalSecrets that
# reference AWS Secrets Manager.

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "external_secrets_status" {
  description = "Status of the External Secrets Operator Helm release"
  value       = var.enable_external_secrets ? helm_release.external_secrets[0].status : "disabled"
}

output "external_secrets_namespace" {
  description = "Namespace where External Secrets Operator is installed"
  value       = var.enable_external_secrets ? kubernetes_namespace.external_secrets[0].metadata[0].name : "disabled"
}

output "external_secrets_role_arn" {
  description = "IAM Role ARN for External Secrets Operator"
  value       = var.enable_external_secrets ? aws_iam_role.external_secrets[0].arn : "disabled"
}

output "cluster_secret_store_name" {
  description = "Name of the ClusterSecretStore for AWS Secrets Manager (managed by ArgoCD)"
  value       = "aws-secrets-manager"
}
