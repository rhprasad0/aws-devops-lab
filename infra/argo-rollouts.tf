# Week 9: Argo Rollouts Controller Installation
#
# Argo Rollouts provides advanced deployment strategies like:
# - Canary deployments (gradual traffic shifting)
# - Blue/Green deployments (instant traffic switching)
# - Progressive delivery with automated analysis
#
# WHY use Argo Rollouts instead of standard Kubernetes Deployments?
# - Standard K8s RollingUpdate only controls pod replacement speed
# - Argo Rollouts controls actual TRAFFIC shifting with precise percentages
# - Enables automated rollback based on metrics/analysis
# - Integrates with service meshes and ingress controllers for true traffic splitting
#
# COST IMPACT: Negligible - controller runs as a small pod (~50m CPU, 64Mi memory)
# No additional AWS resources are created.

resource "kubernetes_namespace" "argo_rollouts" {
  count = var.enable_argo_rollouts ? 1 : 0
  
  depends_on = [module.eks.aws_eks_cluster]
  
  metadata {
    name = "argo-rollouts"
    labels = {
      name                     = "argo-rollouts"
      "app.kubernetes.io/name" = "argo-rollouts"
    }
  }
}

resource "helm_release" "argo_rollouts" {
  count = var.enable_argo_rollouts ? 1 : 0
  
  depends_on = [
    module.eks.aws_eks_cluster,
    kubernetes_namespace.argo_rollouts,
    module.eks
  ]
  
  name       = "argo-rollouts"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-rollouts"
  namespace  = kubernetes_namespace.argo_rollouts[0].metadata[0].name
  version    = "2.37.7"  # Latest stable version as of Nov 2024
  
  # Wait for controller to be fully ready
  wait          = true
  wait_for_jobs = true
  timeout       = 300  # 5 minutes timeout
  
  values = [
    yamlencode({
      # Controller configuration
      controller = {
        # Single replica for lab (cost-effective)
        replicas = 1
        
        # Resource limits for cost control
        resources = {
          limits = {
            cpu    = "200m"   # 0.2 CPU cores max
            memory = "256Mi"  # 256 MB RAM max
          }
          requests = {
            cpu    = "50m"    # 0.05 CPU cores requested
            memory = "64Mi"   # 64 MB RAM requested
          }
        }
        
        # Metrics for Prometheus (useful for Week 10 observability)
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = false  # Enable if you have Prometheus Operator
          }
        }
      }
      
      # Dashboard for visualizing rollouts (optional but helpful for learning)
      dashboard = {
        enabled = true
        
        # Resource limits for dashboard
        resources = {
          limits = {
            cpu    = "100m"
            memory = "128Mi"
          }
          requests = {
            cpu    = "50m"
            memory = "64Mi"
          }
        }
        
        # Use ClusterIP - access via port-forward
        service = {
          type = "ClusterIP"
        }
      }
      
      # Install Rollout CRDs with the chart
      installCRDs = true
    })
  ]
}

# Output for verification
output "argo_rollouts_status" {
  description = "Status of the Argo Rollouts Helm release"
  value       = var.enable_argo_rollouts ? helm_release.argo_rollouts[0].status : "disabled"
}

output "argo_rollouts_dashboard_command" {
  description = "Command to access Argo Rollouts dashboard"
  value       = var.enable_argo_rollouts ? "kubectl port-forward svc/argo-rollouts-dashboard -n argo-rollouts 3100:3100" : "disabled"
}
