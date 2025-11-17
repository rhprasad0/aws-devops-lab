# Week 4: AWS Load Balancer Controller IAM Setup
#
# This creates the IAM role and policy needed for the AWS Load Balancer Controller.
# The controller needs AWS permissions to create and manage ALBs, target groups, and listeners.
#
# Key Concepts:
# - IRSA (IAM Roles for Service Accounts): Modern way to give Kubernetes pods AWS permissions
# - Least Privilege: Only the minimum permissions needed for ALB management
# - Trust Policy: Defines WHO can assume this role (EKS ServiceAccount)
# - Permission Policy: Defines WHAT actions the role can perform

# ============================================================================
# POD IDENTITY TRUST POLICY - Who can assume this role?
# ============================================================================

# Pod Identity uses a simpler trust policy than IRSA.
# The EKS Pod Identity service handles the authentication details.
# 
# How Pod Identity works:
# 1. Create Pod Identity Association linking ServiceAccount to IAM role
# 2. EKS Pod Identity Agent automatically provides AWS credentials to pods
# 3. No OIDC conditions or ServiceAccount annotations needed
# 4. Simpler and more reliable than IRSA
data "aws_iam_policy_document" "aws_load_balancer_controller_assume_role" {
  statement {
    effect = "Allow"
    
    # Pod Identity uses the standard EKS Pod Identity service principal
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }
}

# ============================================================================
# PERMISSION POLICY - What can this role do?
# ============================================================================

# This policy defines the AWS permissions needed by the Load Balancer Controller.
# Based on the official AWS policy but with explanations for each permission group.
data "aws_iam_policy_document" "aws_load_balancer_controller_policy" {
  
  # EC2 Permissions: Network discovery and ENI management
  # The controller needs to understand your VPC topology to place ALBs correctly
  statement {
    sid    = "EC2NetworkDiscovery"
    effect = "Allow"
    actions = [
      "ec2:DescribeVpcs",                # Find which VPC to create ALB in
      "ec2:DescribeSubnets",             # Choose subnets for ALB placement
      "ec2:DescribeSecurityGroups",      # Manage ALB security groups
      "ec2:GetSecurityGroupsForVpc",     # List security groups in VPC
      "ec2:DescribeAvailabilityZones",   # Multi-AZ ALB placement
      "ec2:DescribeInternetGateways",    # For internet-facing ALBs
      "ec2:DescribeInstances",           # Target discovery (though we use IP mode)
      "ec2:DescribeTags",                # Resource filtering and management
      "ec2:CreateTags",                  # Tag resources for organization
      "ec2:DescribeAccountAttributes",   # Account limits and features
      "ec2:DescribeAddresses",           # Elastic IP management
      "ec2:GetCoipCidrAuthorizationAssociation",  # For Outposts support
      "ec2:DescribeCoipCidrBlocks"       # For Outposts support
    ]
    resources = ["*"]
  }
  
  # Network Interface Management: Required for IP target mode
  # In IP target mode, ALB creates ENIs to reach pod IPs directly (bypasses NodePort)
  statement {
    sid    = "EC2NetworkInterfaceManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",           # Create ENIs for ALB
      "ec2:DeleteNetworkInterface",           # Clean up ENIs when ALB deleted
      "ec2:DescribeNetworkInterfaces",        # Monitor ENI status
      "ec2:ModifyNetworkInterfaceAttribute",  # Configure ENI settings
      "ec2:CreateNetworkInterfacePermission", # Grant permissions to ENIs
      "ec2:DeleteNetworkInterfacePermission", # Revoke ENI permissions
      "ec2:DescribeNetworkInterfacePermissions"
    ]
    resources = ["*"]
  }
  
  # Security Group Management: Required for ALB security groups
  statement {
    sid    = "EC2SecurityGroupManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",              # Create security groups for ALB
      "ec2:DeleteSecurityGroup",              # Clean up security groups
      "ec2:AuthorizeSecurityGroupIngress",    # Add inbound rules
      "ec2:AuthorizeSecurityGroupEgress",     # Add outbound rules  
      "ec2:RevokeSecurityGroupIngress",       # Remove inbound rules
      "ec2:RevokeSecurityGroupEgress"         # Remove outbound rules
    ]
    resources = ["*"]
  }
  
  # Load Balancer Management: Core ALB operations
  statement {
    sid    = "ELBManagement"
    effect = "Allow"
    actions = [
      # Discovery operations
      "elasticloadbalancing:DescribeAccountLimits",
      "elasticloadbalancing:DescribeClientVpnConnections", 
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes", 
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
      
      # ALB lifecycle (create from Ingress, delete when Ingress removed)
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:UpdateLoadBalancerAttribute",  # Missing: was ModifyLoadBalancerAttributes
      "elasticloadbalancing:DeleteLoadBalancer",
      
      # Listener management (HTTP/HTTPS endpoints on ALB)
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:UpdateListener",              # Missing: was ModifyListener
      "elasticloadbalancing:DeleteListener",
      
      # Rule management (path-based routing, host-based routing)
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:UpdateRule",                  # Missing: was ModifyRule
      "elasticloadbalancing:DeleteRule"
    ]
    resources = ["*"]
  }
  
  # Target Group Management: Where ALB sends traffic
  statement {
    sid    = "ELBTargetGroupManagement"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateTargetGroup",           # Create target group for service
      "elasticloadbalancing:DeleteTargetGroup",           # Clean up when service deleted
      "elasticloadbalancing:ModifyTargetGroupAttribute",  # Health check configuration (official name)
      "elasticloadbalancing:RegisterTargets",             # Add healthy pod IPs
      "elasticloadbalancing:DeregisterTargets"            # Remove unhealthy/deleted pod IPs
    ]
    resources = ["*"]
  }
  
  # Tagging: Resource management and cost allocation
  statement {
    sid    = "ELBTagging"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddTags",     # Tag ALBs for organization
      "elasticloadbalancing:RemoveTags"   # Clean up tags
    ]
    resources = ["*"]
  }
  
  # IAM: Service-linked role creation (one-time per AWS account)
  statement {
    sid    = "IAMServiceLinkedRole"
    effect = "Allow"
    actions = [
      "iam:CreateServiceLinkedRole",  # Create ELB service-linked role if needed
      "iam:GetRole"                   # Verify role exists
    ]
    resources = ["*"]
  }
  
  # Identity verification
  statement {
    sid       = "STSIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

# ============================================================================
# CREATE IAM ROLE AND POLICY
# ============================================================================

# Create the IAM role that the Load Balancer Controller will assume
resource "aws_iam_role" "aws_load_balancer_controller" {
  name = "${var.env}-aws-load-balancer-controller-role"
  
  # Use the Pod Identity trust policy defined above
  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume_role.json
  
  tags = {
    Name        = "${var.env}-aws-load-balancer-controller-role"
    Description = "IAM role for AWS Load Balancer Controller with Pod Identity"
    Component   = "load-balancer-controller"
    Week        = "4"
  }
}

# Create the IAM policy with the permissions defined above
resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "${var.env}-AWSLoadBalancerControllerIAMPolicy"
  description = "IAM policy for AWS Load Balancer Controller - Week 4"
  
  # Use the permission policy defined above
  policy = data.aws_iam_policy_document.aws_load_balancer_controller_policy.json
  
  tags = {
    Name      = "${var.env}-AWSLoadBalancerControllerIAMPolicy"
    Component = "load-balancer-controller"
    Week      = "4"
  }
}

# Attach the policy to the role
# This connects the role (what can be assumed) with the policy (what permissions are granted)
resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  role       = aws_iam_role.aws_load_balancer_controller.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}

# ============================================================================
# POD IDENTITY ASSOCIATION - Link ServiceAccount to IAM Role
# ============================================================================

# This replaces the ServiceAccount annotation approach (IRSA).
# Pod Identity Association directly links a ServiceAccount to an IAM role.
resource "aws_eks_pod_identity_association" "aws_load_balancer_controller" {
  depends_on = [
    module.eks.aws_eks_cluster,
    kubernetes_service_account.aws_load_balancer_controller,
    aws_iam_role_policy_attachment.aws_load_balancer_controller
  ]
  
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.aws_load_balancer_controller.arn
  
  tags = {
    Name      = "${var.env}-aws-load-balancer-controller-pod-identity"
    Component = "load-balancer-controller"
    Week      = "4"
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

# Output the role ARN - we'll need this for the Kubernetes ServiceAccount annotation
output "aws_load_balancer_controller_role_arn" {
  description = "ARN of the IAM role for AWS Load Balancer Controller"
  value       = aws_iam_role.aws_load_balancer_controller.arn
}

# Output the policy ARN for reference
output "aws_load_balancer_controller_policy_arn" {
  description = "ARN of the IAM policy for AWS Load Balancer Controller"
  value       = aws_iam_policy.aws_load_balancer_controller.arn
}
