# Week 4: Kubernetes ServiceAccount for AWS Load Balancer Controller
#
# With Pod Identity, ServiceAccounts don't need IAM role annotations.
# The Pod Identity Association (in load-balancer-iam.tf) handles the AWS credentials.
#
# How Pod Identity works:
# 1. Pod uses this ServiceAccount
# 2. EKS Pod Identity Agent sees the Pod Identity Association
# 3. Agent provides temporary AWS credentials directly to the pod
# 4. Pod can now make AWS API calls using those credentials
#
# Benefits over IRSA:
# - No annotations needed on ServiceAccount
# - Simpler IAM trust policies
# - Better performance and reliability

# Create the ServiceAccount in kube-system namespace
resource "kubernetes_service_account" "aws_load_balancer_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    
    # No IAM role annotation needed with Pod Identity!
    # The Pod Identity Association handles AWS credentials
    
    # Standard labels for organization
    labels = {
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
      "app.kubernetes.io/component" = "controller"
      "app.kubernetes.io/part-of"   = "eks-ephemeral-lab"
    }
  }
}

# Output the ServiceAccount name for reference
output "aws_load_balancer_controller_service_account_name" {
  description = "Name of the Kubernetes ServiceAccount for AWS Load Balancer Controller"
  value       = kubernetes_service_account.aws_load_balancer_controller.metadata[0].name
}
