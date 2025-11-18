# ExternalDNS Community Add-on - Week 5 Task 3
#
# WHAT: Installs ExternalDNS as an EKS Community Add-on to automatically manage Route 53 DNS records
# WHY: Eliminates manual DNS management - when you create an Ingress with a hostname,
#      ExternalDNS automatically creates the corresponding A record in Route 53
# HOW: Uses AWS-managed community add-on with Pod Identity for secure AWS API access
#
# SECURITY: Uses existing least-privilege IAM role (external-dns-iam.tf) scoped to ryans-lab.click zone only
# COST: ~$0.50/month for Route 53 hosted zone + minimal query costs (~$0.01/session)
#
# Based on: https://docs.aws.amazon.com/eks/latest/userguide/community-addons.html
# Alternative to: Manual Helm installation or kubectl manifests

# Create namespace for ExternalDNS
# WHY: EKS add-on expects this namespace to exist before installation
# NOTE: Could use kubectl but Terraform ensures consistent state management
resource "kubernetes_namespace" "external_dns" {
  metadata {
    name = "external-dns"
    
    # LABELS: Standard Kubernetes labels for identification
    labels = {
      name = "external-dns"
      "app.kubernetes.io/name" = "external-dns"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Install ExternalDNS as EKS Community Add-on (AWS recommended approach)
# This is preferred over manual Helm/kubectl because:
# - AWS validates version compatibility with EKS
# - Managed lifecycle (install/update/remove via AWS APIs)
# - Consistent deployment across clusters
# - Container images hosted in AWS ECR (security scanned)
resource "aws_eks_addon" "external_dns" {
  cluster_name = module.eks.cluster_name
  addon_name   = "external-dns"
  
  # Use latest available version - AWS ensures compatibility
  resolve_conflicts_on_create = "OVERWRITE"  # Replace any existing manual installation
  resolve_conflicts_on_update = "OVERWRITE"  # Allow updates to override custom settings
  
  # ExternalDNS configuration - equivalent to command-line args
  configuration_values = jsonencode({
    # SECURITY: Restrict to only your hosted zone (prevents managing other domains)
    domainFilters = ["ryans-lab.click"]
    
    # POLICY: "sync" means ExternalDNS owns all records it creates
    # Alternative: "upsert-only" (safer but doesn't clean up deleted ingresses)
    policy = "sync"
    
    # REGISTRY: Use TXT records to track ownership (prevents conflicts)
    # Creates TXT records like "heritage=external-dns,external-dns/owner=eks-lab"
    registry = "txt"
    txtOwnerId = "eks-lab"  # Unique identifier for this cluster
    
    # OBSERVABILITY: Info level provides good balance of detail vs noise
    logLevel = "info"
    
    # COST OPTIMIZATION: Minimal resources for lab environment
    # Production: Consider higher limits based on number of ingresses
    resources = {
      requests = {
        cpu    = "50m"    # 0.05 CPU cores
        memory = "64Mi"   # 64 MiB RAM
      }
      limits = {
        cpu    = "100m"   # Max 0.1 CPU cores
        memory = "128Mi"  # Max 128 MiB RAM
      }
    }
  })

  # DEPENDENCIES: Ensure namespace, IAM role and Pod Identity are ready before add-on installation
  depends_on = [
    kubernetes_namespace.external_dns,         # Namespace must exist first
    aws_iam_role.external_dns,                # IAM role from external-dns-iam.tf
    aws_eks_pod_identity_association.external_dns  # Pod Identity association below
  ]
}

# Pod Identity Association - Maps Kubernetes ServiceAccount to AWS IAM Role
# WHY Pod Identity vs IRSA: 
# - Simpler setup (no OIDC provider annotations)
# - AWS-native authentication
# - Automatic credential rotation
# - Recommended for new EKS clusters (1.24+)
resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = module.eks.cluster_name
  namespace       = kubernetes_namespace.external_dns.metadata[0].name  # Reference created namespace
  service_account = "external-dns"      # Default service account name for ExternalDNS add-on
  role_arn        = aws_iam_role.external_dns.arn  # References least-privilege role from external-dns-iam.tf
  
  # NOTE: This creates the association but the add-on creates the actual ServiceAccount
  # The add-on will automatically use this Pod Identity for AWS API calls
}
