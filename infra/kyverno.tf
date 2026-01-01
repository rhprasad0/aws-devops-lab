# =============================================================================
# Week 13: Kyverno - Policy Engine for Kubernetes
# =============================================================================
#
# Kyverno is a Kubernetes-native policy engine that validates, mutates, and
# generates configurations using admission control and background scans.
#
# WHY Kyverno instead of OPA Gatekeeper?
# - Native Kubernetes resources (no Rego language to learn)
# - Policies are written in YAML, easier for K8s users
# - Can mutate resources (not just validate)
# - Can generate resources automatically
# - Simpler to debug with familiar K8s patterns
#
# USE CASES for Week 13:
# - Block images with :latest tag
# - Require resource limits on all containers
# - Block privileged containers
# - Require specific labels on resources
#
# COST IMPACT: Negligible - controller runs as small pods (~100m CPU, 256Mi memory)
# No additional AWS resources are created.
# =============================================================================

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "enable_kyverno" {
  description = "Enable Kyverno policy engine"
  type        = bool
  default     = true
}

variable "kyverno_version" {
  description = "Kyverno Helm chart version"
  type        = string
  default     = "3.3.4" # Latest stable v3.3.x as of Dec 2024
}

variable "kyverno_namespace" {
  description = "Kubernetes namespace for Kyverno"
  type        = string
  default     = "kyverno"
}

# -----------------------------------------------------------------------------
# Namespace
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "kyverno" {
  count = var.enable_kyverno ? 1 : 0

  depends_on = [module.eks.aws_eks_cluster]

  metadata {
    name = var.kyverno_namespace
    labels = {
      name                         = "kyverno"
      "app.kubernetes.io/name"     = "kyverno"
      "app.kubernetes.io/instance" = "kyverno"
      # Exempt Kyverno namespace from its own policies to avoid chicken-and-egg
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

# -----------------------------------------------------------------------------
# Kyverno Helm Release
# -----------------------------------------------------------------------------

resource "helm_release" "kyverno" {
  count = var.enable_kyverno ? 1 : 0

  depends_on = [
    module.eks.aws_eks_cluster,
    kubernetes_namespace.kyverno,
    module.eks
  ]

  name       = "kyverno"
  repository = "https://kyverno.github.io/kyverno"
  chart      = "kyverno"
  version    = var.kyverno_version
  namespace  = kubernetes_namespace.kyverno[0].metadata[0].name

  # Wait for Kyverno to be fully ready (important for admission webhook)
  wait          = true
  wait_for_jobs = true
  timeout       = 600 # 10 minutes (CRDs + webhook can take time)

  values = [
    yamlencode({
      # Admission controller configuration
      admissionController = {
        # Single replica for lab (cost-effective)
        replicas = 1

        # Resource limits for cost control
        resources = {
          limits = {
            cpu    = "500m"  # 0.5 CPU cores max
            memory = "512Mi" # 512 MB RAM max
          }
          requests = {
            cpu    = "100m"  # 0.1 CPU cores requested
            memory = "256Mi" # 256 MB RAM requested
          }
        }

        # Container settings
        container = {
          resources = {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
          }
        }
      }

      # Background controller - scans existing resources
      backgroundController = {
        replicas = 1

        resources = {
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
          requests = {
            cpu    = "50m"
            memory = "128Mi"
          }
        }
      }

      # Cleanup controller - handles policy cleanup
      cleanupController = {
        replicas = 1

        resources = {
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
          requests = {
            cpu    = "50m"
            memory = "128Mi"
          }
        }
      }

      # Reports controller - generates policy reports
      reportsController = {
        replicas = 1

        resources = {
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
          requests = {
            cpu    = "50m"
            memory = "128Mi"
          }
        }
      }

      # Install CRDs with the chart
      crds = {
        install = true
      }

      # Webhook configuration
      webhooksCleanup = {
        enabled = true
      }

      # Exclude system namespaces from policies by default
      # This prevents Kyverno from blocking critical system components
      config = {
        excludeNamespaces = [
          "kube-system",
          "kube-node-lease",
          "kube-public",
          "kyverno",
          "argocd",
          "argo-rollouts",
          "cert-manager",
          "amazon-cloudwatch",
          "external-secrets"  # Week 13: External Secrets Operator
        ]
      }
    })
  ]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "kyverno_status" {
  description = "Status of the Kyverno Helm release"
  value       = var.enable_kyverno ? helm_release.kyverno[0].status : "disabled"
}

output "kyverno_namespace" {
  description = "Namespace where Kyverno is installed"
  value       = var.enable_kyverno ? kubernetes_namespace.kyverno[0].metadata[0].name : "disabled"
}

output "kyverno_version" {
  description = "Installed Kyverno Helm chart version"
  value       = var.enable_kyverno ? helm_release.kyverno[0].version : "disabled"
}
