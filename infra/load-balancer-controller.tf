# Week 4: AWS Load Balancer Controller Helm Installation
#
# This installs the actual controller that watches Ingress resources and creates ALBs.
# The controller runs as a deployment in the kube-system namespace.
#
# What the controller does:
# 1. Watches for Ingress resources with ALB annotations
# 2. Creates AWS ALB + Target Groups + Listeners automatically  
# 3. Registers/deregisters pod IPs as targets when pods scale
# 4. Cleans up AWS resources when Ingress is deleted

# Install AWS Load Balancer Controller via Helm
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1"  # Latest stable version as of Nov 2024
  
  # Wait for all resources to be ready before marking as successful
  wait          = true
  wait_for_jobs = true
  timeout       = 300  # 5 minutes timeout
  
  # Configuration values for the controller
  values = [
    yamlencode({
      # REQUIRED: Tell the controller which EKS cluster it's managing
      clusterName = module.eks.cluster_name
      
      # Use our pre-created ServiceAccount with IRSA
      serviceAccount = {
        create = false  # Don't create new ServiceAccount
        name   = kubernetes_service_account.aws_load_balancer_controller.metadata[0].name
      }
      
      # Resource limits for cost control (lab-appropriate)
      resources = {
        limits = {
          cpu    = "200m"    # 0.2 CPU cores max
          memory = "500Mi"   # 500 MB RAM max  
        }
        requests = {
          cpu    = "100m"    # 0.1 CPU cores requested
          memory = "200Mi"   # 200 MB RAM requested
        }
      }
      
      # Single replica for lab (not HA, but cost-effective)
      replicaCount = 1
      
      # AWS region where ALBs will be created
      region = var.region
      
      # Default tags applied to all ALBs created by this controller
      defaultTags = {
        Environment = var.env
        ManagedBy   = "aws-load-balancer-controller"
        Project     = "eks-ephemeral-lab"
        Week        = "4"
      }
      
      # Enable important features
      enableServiceMutatorWebhook = true  # Allows controller to modify Service resources
      enableEndpointSlices        = true  # Better performance for large clusters
      
      # Logging configuration
      logLevel = "info"  # Options: error, warn, info, debug
      
      # Security context - run as non-root
      securityContext = {
        runAsNonRoot = true
        runAsUser    = 65534  # 'nobody' user
      }
    })
  ]
  
  # Dependencies - ensure prerequisites exist
  depends_on = [
    kubernetes_service_account.aws_load_balancer_controller,
    aws_iam_role_policy_attachment.aws_load_balancer_controller
  ]
}

# Output controller information
output "aws_load_balancer_controller_chart_version" {
  description = "Version of the AWS Load Balancer Controller Helm chart"
  value       = helm_release.aws_load_balancer_controller.version
}

output "aws_load_balancer_controller_status" {
  description = "Status of the AWS Load Balancer Controller Helm release"
  value       = helm_release.aws_load_balancer_controller.status
}
