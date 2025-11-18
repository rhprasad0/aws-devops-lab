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

# Official AWS Load Balancer Controller IAM policy (v2.14.1)
# Source: https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json
# This ensures least-privilege permissions with proper resource constraints and security conditions
data "aws_iam_policy_document" "aws_load_balancer_controller_policy" {
  # IAM: Service-linked role creation (restricted to ELB service only)
  statement {
    effect = "Allow"
    actions = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }

  # EC2 and ELB: Read-only discovery operations
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:GetCoipPoolUsage",
      "ec2:DescribeCoipPools",
      "ec2:GetSecurityGroupsForVpc",
      "ec2:DescribeIpamPools",
      "ec2:DescribeRouteTables",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTrustStores",
      "elasticloadbalancing:DescribeListenerAttributes",
      "elasticloadbalancing:DescribeCapacityReservation"
    ]
    resources = ["*"]
  }

  # Integration services: ACM, WAF, Shield, Cognito
  statement {
    effect = "Allow"
    actions = [
      "cognito-idp:DescribeUserPoolClient",
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "iam:ListServerCertificates",
      "iam:GetServerCertificate",
      "waf-regional:GetWebACL",
      "waf-regional:GetWebACLForResource",
      "waf-regional:AssociateWebACL",
      "waf-regional:DisassociateWebACL",
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "shield:GetSubscriptionState",
      "shield:DescribeProtection",
      "shield:CreateProtection",
      "shield:DeleteProtection"
    ]
    resources = ["*"]
  }

  # EC2: Security group ingress/egress (no conditions - needed for flexibility)
  statement {
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress"
    ]
    resources = ["*"]
  }

  # EC2: Security group creation (no conditions)
  statement {
    effect = "Allow"
    actions = ["ec2:CreateSecurityGroup"]
    resources = ["*"]
  }

  # EC2: Tag security groups during creation (requires cluster tag)
  statement {
    effect = "Allow"
    actions = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:*:*:security-group/*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateSecurityGroup"]
    }
    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  # EC2: Tag/untag existing security groups (only controller-managed)
  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags"
    ]
    resources = ["arn:aws:ec2:*:*:security-group/*"]
    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["true"]
    }
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  # EC2: Modify/delete security groups (only controller-managed)
  statement {
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DeleteSecurityGroup"
    ]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  # ELB: Create load balancers and target groups (requires cluster tag)
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup"
    ]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  # ELB: Listener and rule management (no conditions)
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule"
    ]
    resources = ["*"]
  }

  # ELB: Tag load balancers and target groups (only controller-managed)
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags"
    ]
    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
    ]
    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["true"]
    }
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  # ELB: Tag listeners and rules (no conditions)
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags"
    ]
    resources = [
      "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
    ]
  }

  # ELB: Modify load balancers and target groups (only controller-managed)
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyListenerAttributes",
      "elasticloadbalancing:ModifyCapacityReservation",
      "elasticloadbalancing:ModifyIpPools"
    ]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  # ELB: Tag during creation (requires cluster tag)
  statement {
    effect = "Allow"
    actions = ["elasticloadbalancing:AddTags"]
    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "elasticloadbalancing:CreateAction"
      values   = ["CreateTargetGroup", "CreateLoadBalancer"]
    }
    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  # ELB: Target registration (no conditions)
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets"
    ]
    resources = ["arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"]
  }

  # ELB: Listener and rule modifications (no conditions)
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:SetWebAcl",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:SetRulePriorities"
    ]
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
