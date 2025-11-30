# =============================================================================
# Week 12: Karpenter - Automatic Node Provisioning
# =============================================================================
#
# Karpenter is an open-source Kubernetes node autoscaler that provisions
# right-sized compute capacity in response to pending pods. Unlike Cluster
# Autoscaler, Karpenter:
#
# 1. Provisions nodes directly via EC2 APIs (faster than ASG scaling)
# 2. Selects optimal instance types based on pod requirements
# 3. Consolidates workloads to reduce costs
# 4. Handles Spot interruptions natively
#
# This setup uses EKS Pod Identity (not IRSA) for simpler IAM management.
#
# COST ESTIMATE: ~$0.50/day for Karpenter controller (runs on existing nodes)
#                Node costs depend on workload - Spot can save 60-90%
# =============================================================================

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "enable_karpenter" {
  description = "Enable Karpenter node autoscaler"
  type        = bool
  default     = true
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.0.8" # Latest stable v1.0.x as of Nov 2024
}

variable "karpenter_namespace" {
  description = "Kubernetes namespace for Karpenter"
  type        = string
  default     = "kube-system"
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
# Note: aws_caller_identity is defined in security.tf

data "aws_partition" "current" {}

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# EC2 Spot Service-Linked Role
# -----------------------------------------------------------------------------
# AWS requires a service-linked role to manage Spot instances. This role is
# created once per account and allows EC2 to:
# - Request and manage Spot capacity
# - Handle Spot interruptions
# - Access Spot pricing information
#
# Note: This role can only exist once per account. If it already exists,
# Terraform will import it. The role is account-wide, not region-specific.

resource "aws_iam_service_linked_role" "spot" {
  count = var.enable_karpenter ? 1 : 0

  aws_service_name = "spot.amazonaws.com"
  description      = "Service-linked role for EC2 Spot Instances - enables Karpenter Spot provisioning"

  # This role is managed by AWS and cannot be customized
  # It will be named: AWSServiceRoleForEC2Spot

  tags = {
    Name      = "AWSServiceRoleForEC2Spot"
    Component = "karpenter"
    Week      = "12"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for Karpenter Controller (Pod Identity)
# -----------------------------------------------------------------------------
# This role allows the Karpenter controller pod to:
# - Launch and terminate EC2 instances
# - Create and manage launch templates
# - Pass roles to EC2 instances
# - Read SSM parameters for AMI discovery
# - Manage SQS queues for Spot interruption handling

resource "aws_iam_role" "karpenter_controller" {
  count = var.enable_karpenter ? 1 : 0

  name = "${var.env}-karpenter-controller-role"

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
    Name      = "${var.env}-karpenter-controller-role"
    Component = "karpenter"
    Week      = "12"
  }
}

# Karpenter Controller IAM Policy
# Based on: https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/
resource "aws_iam_policy" "karpenter_controller" {
  count = var.enable_karpenter ? 1 : 0

  name        = "${var.env}-KarpenterControllerPolicy"
  description = "IAM policy for Karpenter controller - Week 12"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # EC2: Instance lifecycle management
      {
        Sid    = "EC2NodeManagement"
        Effect = "Allow"
        Action = [
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateTags",
          "ec2:DeleteLaunchTemplate",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
          "ec2:RunInstances",
          "ec2:TerminateInstances"
        ]
        Resource = "*"
      },
      # EC2: Conditional instance termination (only Karpenter-managed nodes)
      {
        Sid      = "EC2TerminateKarpenterNodes"
        Effect   = "Allow"
        Action   = "ec2:TerminateInstances"
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      # IAM: Pass role to EC2 instances
      {
        Sid      = "PassNodeRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.karpenter_node[0].arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },
      # IAM: Create instance profile for nodes
      # Karpenter v1.0+ creates instance profiles with pattern: {cluster-name}_{hash}
      {
        Sid    = "InstanceProfileManagement"
        Effect = "Allow"
        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${module.eks.cluster_name}_*"
      },
      # SSM: Read EKS-optimized AMI parameters
      {
        Sid      = "SSMReadAMI"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.id}::parameter/aws/service/eks/optimized-ami/*"
      },
      # EKS: Describe cluster for configuration
      {
        Sid      = "EKSDescribeCluster"
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = module.eks.cluster_arn
      },
      # Pricing: Get on-demand pricing for cost optimization
      {
        Sid      = "PricingAccess"
        Effect   = "Allow"
        Action   = "pricing:GetProducts"
        Resource = "*"
      },
      # SQS: Handle Spot interruption notifications (optional but recommended)
      {
        Sid    = "SQSInterruptionHandling"
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage"
        ]
        Resource = var.enable_karpenter ? aws_sqs_queue.karpenter_interruption[0].arn : "*"
      }
    ]
  })

  tags = {
    Name      = "${var.env}-KarpenterControllerPolicy"
    Component = "karpenter"
    Week      = "12"
  }
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  count = var.enable_karpenter ? 1 : 0

  role       = aws_iam_role.karpenter_controller[0].name
  policy_arn = aws_iam_policy.karpenter_controller[0].arn
}

# -----------------------------------------------------------------------------
# IAM Role for Karpenter-Provisioned Nodes
# -----------------------------------------------------------------------------
# This role is assumed by EC2 instances that Karpenter launches.
# It needs standard EKS worker node permissions.

resource "aws_iam_role" "karpenter_node" {
  count = var.enable_karpenter ? 1 : 0

  name = "${var.env}-karpenter-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name      = "${var.env}-karpenter-node-role"
    Component = "karpenter"
    Week      = "12"
  }
}

# Attach required managed policies for EKS worker nodes
resource "aws_iam_role_policy_attachment" "karpenter_node_eks_worker" {
  count = var.enable_karpenter ? 1 : 0

  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  count = var.enable_karpenter ? 1 : 0

  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  count = var.enable_karpenter ? 1 : 0

  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  count = var.enable_karpenter ? 1 : 0

  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile for Karpenter nodes
resource "aws_iam_instance_profile" "karpenter_node" {
  count = var.enable_karpenter ? 1 : 0

  name = "${var.env}-KarpenterNodeInstanceProfile"
  role = aws_iam_role.karpenter_node[0].name

  tags = {
    Name      = "${var.env}-KarpenterNodeInstanceProfile"
    Component = "karpenter"
    Week      = "12"
  }
}

# -----------------------------------------------------------------------------
# EKS Access Entry for Karpenter Nodes
# -----------------------------------------------------------------------------
# Allow Karpenter-provisioned nodes to join the cluster

resource "aws_eks_access_entry" "karpenter_node" {
  count = var.enable_karpenter ? 1 : 0

  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.karpenter_node[0].arn
  type          = "EC2_LINUX"

  tags = {
    Name      = "${var.env}-karpenter-node-access"
    Component = "karpenter"
    Week      = "12"
  }
}

# -----------------------------------------------------------------------------
# Pod Identity Association for Karpenter Controller
# -----------------------------------------------------------------------------

resource "aws_eks_pod_identity_association" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.karpenter_controller
  ]

  cluster_name    = module.eks.cluster_name
  namespace       = var.karpenter_namespace
  service_account = "karpenter"
  role_arn        = aws_iam_role.karpenter_controller[0].arn

  tags = {
    Name      = "${var.env}-karpenter-pod-identity"
    Component = "karpenter"
    Week      = "12"
  }
}

# -----------------------------------------------------------------------------
# SQS Queue for Spot Interruption Handling
# -----------------------------------------------------------------------------
# Karpenter can receive Spot interruption notifications via SQS,
# allowing graceful pod eviction before instances are terminated.

resource "aws_sqs_queue" "karpenter_interruption" {
  count = var.enable_karpenter ? 1 : 0

  name                      = "${var.env}-karpenter-interruption"
  message_retention_seconds = 300 # 5 minutes (Spot gives 2 min warning)
  sqs_managed_sse_enabled   = true

  tags = {
    Name      = "${var.env}-karpenter-interruption"
    Component = "karpenter"
    Week      = "12"
  }
}

# SQS Queue Policy - Allow EventBridge to send messages
resource "aws_sqs_queue_policy" "karpenter_interruption" {
  count = var.enable_karpenter ? 1 : 0

  queue_url = aws_sqs_queue.karpenter_interruption[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridge"
        Effect = "Allow"
        Principal = {
          Service = ["events.amazonaws.com", "sqs.amazonaws.com"]
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.karpenter_interruption[0].arn
      }
    ]
  })
}

# EventBridge Rules for Spot Interruption Events
resource "aws_cloudwatch_event_rule" "karpenter_spot_interruption" {
  count = var.enable_karpenter ? 1 : 0

  name        = "${var.env}-karpenter-spot-interruption"
  description = "Capture EC2 Spot Instance Interruption Warnings"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })

  tags = {
    Name      = "${var.env}-karpenter-spot-interruption"
    Component = "karpenter"
    Week      = "12"
  }
}

resource "aws_cloudwatch_event_target" "karpenter_spot_interruption" {
  count = var.enable_karpenter ? 1 : 0

  rule      = aws_cloudwatch_event_rule.karpenter_spot_interruption[0].name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter_interruption[0].arn
}

# EventBridge Rule for Instance Rebalance Recommendations
resource "aws_cloudwatch_event_rule" "karpenter_rebalance" {
  count = var.enable_karpenter ? 1 : 0

  name        = "${var.env}-karpenter-rebalance"
  description = "Capture EC2 Instance Rebalance Recommendations"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })

  tags = {
    Name      = "${var.env}-karpenter-rebalance"
    Component = "karpenter"
    Week      = "12"
  }
}

resource "aws_cloudwatch_event_target" "karpenter_rebalance" {
  count = var.enable_karpenter ? 1 : 0

  rule      = aws_cloudwatch_event_rule.karpenter_rebalance[0].name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter_interruption[0].arn
}

# EventBridge Rule for Scheduled Instance Changes (maintenance)
resource "aws_cloudwatch_event_rule" "karpenter_scheduled_change" {
  count = var.enable_karpenter ? 1 : 0

  name        = "${var.env}-karpenter-scheduled-change"
  description = "Capture AWS Health Events for scheduled changes"

  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
  })

  tags = {
    Name      = "${var.env}-karpenter-scheduled-change"
    Component = "karpenter"
    Week      = "12"
  }
}

resource "aws_cloudwatch_event_target" "karpenter_scheduled_change" {
  count = var.enable_karpenter ? 1 : 0

  rule      = aws_cloudwatch_event_rule.karpenter_scheduled_change[0].name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter_interruption[0].arn
}

# EventBridge Rule for Instance State Changes
resource "aws_cloudwatch_event_rule" "karpenter_state_change" {
  count = var.enable_karpenter ? 1 : 0

  name        = "${var.env}-karpenter-state-change"
  description = "Capture EC2 Instance State-change Notifications"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })

  tags = {
    Name      = "${var.env}-karpenter-state-change"
    Component = "karpenter"
    Week      = "12"
  }
}

resource "aws_cloudwatch_event_target" "karpenter_state_change" {
  count = var.enable_karpenter ? 1 : 0

  rule      = aws_cloudwatch_event_rule.karpenter_state_change[0].name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter_interruption[0].arn
}

# -----------------------------------------------------------------------------
# Subnet and Security Group Tags for Karpenter Discovery
# -----------------------------------------------------------------------------
# Karpenter discovers subnets and security groups by tags.
# We need to tag the private subnets and cluster security group.

# Note: Private subnet tags are managed via the VPC module's private_subnet_tags
# in main.tf to avoid conflicts. The karpenter.sh/discovery tag is conditionally
# added there when enable_karpenter = true.

resource "aws_ec2_tag" "cluster_security_group_karpenter" {
  count = var.enable_karpenter ? 1 : 0

  resource_id = module.eks.cluster_primary_security_group_id
  key         = "karpenter.sh/discovery"
  value       = module.eks.cluster_name
}

# -----------------------------------------------------------------------------
# Karpenter Helm Release
# -----------------------------------------------------------------------------

resource "helm_release" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  depends_on = [
    module.eks,
    aws_eks_pod_identity_association.karpenter,
    aws_eks_access_entry.karpenter_node,
    aws_iam_instance_profile.karpenter_node,
    aws_ec2_tag.cluster_security_group_karpenter
  ]

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version
  namespace  = var.karpenter_namespace

  # Wait for Karpenter to be ready
  wait          = true
  wait_for_jobs = true
  timeout       = 600

  # Karpenter configuration
  values = [
    yamlencode({
      # Settings for Karpenter controller
      settings = {
        clusterName       = module.eks.cluster_name
        clusterEndpoint   = module.eks.cluster_endpoint
        interruptionQueue = aws_sqs_queue.karpenter_interruption[0].name
      }

      # ServiceAccount configuration - don't create, we use Pod Identity
      serviceAccount = {
        create = true
        name   = "karpenter"
        # No annotations needed with Pod Identity
      }

      # Controller configuration
      controller = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }
      }

      # Run on existing managed node group (not on Karpenter-provisioned nodes)
      affinity = {
        nodeAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = {
            nodeSelectorTerms = [
              {
                matchExpressions = [
                  {
                    key      = "karpenter.sh/nodepool"
                    operator = "DoesNotExist"
                  }
                ]
              }
            ]
          }
        }
        podAntiAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = [
            {
              topologyKey = "kubernetes.io/hostname"
            }
          ]
        }
      }

      # Tolerations to run on any node
      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
        }
      ]

      # Replicas for HA (single replica for dev, 2+ for prod)
      replicas = 1
    })
  ]
}

# -----------------------------------------------------------------------------
# Karpenter NodePool and EC2NodeClass (Kubernetes Manifests)
# -----------------------------------------------------------------------------
# These define what kinds of nodes Karpenter can provision.
# 
# NOTE: We output these as YAML files instead of using kubernetes_manifest
# because the CRDs don't exist until Karpenter is installed. Apply these
# manifests after terraform apply completes:
#
#   kubectl apply -f ../k8s/karpenter/

resource "local_file" "karpenter_ec2nodeclass" {
  count = var.enable_karpenter ? 1 : 0

  filename = "${path.module}/../k8s/karpenter/ec2nodeclass.yaml"
  content  = <<-YAML
# =============================================================================
# EC2NodeClass - Defines AWS-specific node configuration for Karpenter
# =============================================================================
# This resource tells Karpenter HOW to configure EC2 instances:
# - Which AMI to use
# - What IAM role to assign
# - Which subnets and security groups to use
# - Block device (EBS) configuration
#
# Apply after Karpenter is installed:
#   kubectl apply -f k8s/karpenter/ec2nodeclass.yaml
# =============================================================================
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  # AMI selection - use EKS-optimized AL2023
  # al2023@latest automatically picks the latest EKS-optimized Amazon Linux 2023 AMI
  amiSelectorTerms:
    - alias: al2023@latest

  # IAM role for nodes - must match the role created in Terraform
  role: ${aws_iam_role.karpenter_node[0].name}

  # Subnet discovery - finds subnets tagged with karpenter.sh/discovery
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}

  # Security group discovery - finds SGs tagged with karpenter.sh/discovery
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}

  # Block device configuration - 20GB gp3 root volume
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 20Gi
        volumeType: gp3
        encrypted: true
        deleteOnTermination: true

  # IMDSv2 required for security (prevents SSRF attacks)
  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 2
    httpTokens: required

  # Tags applied to EC2 instances
  tags:
    Name: ${var.env}-karpenter-node
    Component: karpenter
    Week: "12"
    project: eks-ephemeral-lab
    env: ${var.env}
    owner: ${var.owner}
YAML
}

resource "local_file" "karpenter_nodepool" {
  count = var.enable_karpenter ? 1 : 0

  filename = "${path.module}/../k8s/karpenter/nodepool.yaml"
  content  = <<-YAML
# =============================================================================
# NodePool - Defines WHAT kinds of nodes Karpenter can provision
# =============================================================================
# This resource tells Karpenter:
# - What instance types/sizes to use
# - Spot vs On-Demand preferences
# - Resource limits (cost controls)
# - Consolidation behavior
#
# Apply after EC2NodeClass:
#   kubectl apply -f k8s/karpenter/nodepool.yaml
# =============================================================================
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  # Template for nodes created by this pool
  template:
    metadata:
      labels:
        # Note: karpenter.sh/* labels are restricted and auto-applied by Karpenter
        node-type: karpenter
    spec:
      # Reference the EC2NodeClass for AWS-specific config
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default

      # Instance requirements - cost-optimized for learning lab
      requirements:
        # Capacity type: prefer Spot for 60-90% cost savings
        # Falls back to On-Demand if Spot unavailable
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        
        # Architecture: ARM64 (Graviton) for ~20% cost savings over x86
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]
        
        # Instance families: budget-friendly Graviton instances
        # t4g: burstable, m6g/m7g: general purpose, c6g/c7g: compute, r6g: memory
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["t4g", "m6g", "m7g", "c6g", "c7g", "r6g"]
        
        # Instance sizes: small to medium for learning lab
        - key: karpenter.k8s.aws/instance-size
          operator: In
          values: ["small", "medium", "large"]

      # Expire nodes after 24 hours (forces refresh, good for security)
      expireAfter: 24h

  # Disruption settings - aggressive consolidation for cost savings
  disruption:
    # Consolidate when nodes are empty OR underutilized
    consolidationPolicy: WhenEmptyOrUnderutilized
    # Wait 30 seconds before consolidating (allows for pod scheduling)
    consolidateAfter: 30s

  # Resource limits - CRITICAL for cost control!
  # Prevents runaway costs if something goes wrong
  limits:
    cpu: "20"       # Max 20 vCPUs total across all Karpenter nodes
    memory: "40Gi"  # Max 40 GiB memory total

  # Weight for this NodePool (higher = preferred when multiple pools exist)
  weight: 100
YAML
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "karpenter_controller_role_arn" {
  description = "ARN of the Karpenter controller IAM role"
  value       = var.enable_karpenter ? aws_iam_role.karpenter_controller[0].arn : null
}

output "karpenter_node_role_arn" {
  description = "ARN of the Karpenter node IAM role"
  value       = var.enable_karpenter ? aws_iam_role.karpenter_node[0].arn : null
}

output "karpenter_node_instance_profile_name" {
  description = "Name of the Karpenter node instance profile"
  value       = var.enable_karpenter ? aws_iam_instance_profile.karpenter_node[0].name : null
}

output "karpenter_interruption_queue_name" {
  description = "Name of the SQS queue for Karpenter interruption handling"
  value       = var.enable_karpenter ? aws_sqs_queue.karpenter_interruption[0].name : null
}

