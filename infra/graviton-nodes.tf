# Direct EKS Node Group for Graviton (ARM64) Migration
#
# WHY THIS FILE EXISTS:
# terraform-aws-modules/eks v21.0.0 has a bug where the ami_type parameter
# is not properly passed to aws_eks_node_group when using launch templates.
# The module defaults to AL2023_x86_64_STANDARD even when AL2023_ARM_64_STANDARD
# is explicitly configured, causing conflicts with ARM instance types.
#
# SOLUTION:
# Create node group directly using aws_eks_node_group resource, bypassing
# the module entirely. This gives explicit control over ami_type.
#
# COST SAVINGS:
# - 2 × t3.medium (x86) = ~$60/month
# - 2 × t4g.medium (ARM) = ~$48/month
# - Monthly savings: $12 (20% reduction)
# - 16-week lab savings: ~$48

# IAM role for Graviton nodes
# Create a dedicated role for the Graviton node group with required policies
resource "aws_iam_role" "graviton_node_group" {
  name = "${var.env}-graviton-node-group-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "EKSNodeAssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
  
  tags = {
    Name      = "${var.env}-graviton-node-group-role"
    Component = "eks-nodes"
    NodeType  = "graviton-arm64"
  }
}

# Attach required policies for EKS nodes
resource "aws_iam_role_policy_attachment" "graviton_node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.graviton_node_group.name
}

resource "aws_iam_role_policy_attachment" "graviton_node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.graviton_node_group.name
}

resource "aws_iam_role_policy_attachment" "graviton_node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.graviton_node_group.name
}

resource "aws_eks_node_group" "graviton" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "graviton-main"
  node_role_arn   = aws_iam_role.graviton_node_group.arn
  subnet_ids      = module.vpc.private_subnets
  
  # CRITICAL: Explicitly set ARM64 AMI type
  # This is the fix - direct specification bypasses module bug
  ami_type       = "AL2023_ARM_64_STANDARD"
  instance_types = ["t4g.medium"]
  
  # Match cluster version to avoid version skew
  version = "1.32"
  
  # Disk size for node volumes
  disk_size = 20
  
  # Scaling configuration
  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 2
  }
  
  # Update strategy - allow 33% unavailable during updates
  update_config {
    max_unavailable_percentage = 33
  }
  
  # Reasonable timeouts for node group operations
  timeouts {
    create = "15m"
    update = "15m"
    delete = "15m"
  }
  
  # Tags for resource tracking
  tags = {
    Name      = "graviton-main"
    NodeType  = "graviton-arm64"
    Week      = "1-4"
    Component = "compute"
  }
  
  # Ensure cluster and IAM are ready before creating node group
  depends_on = [
    module.eks.cluster_id,
    module.eks.cluster_certificate_authority_data
  ]
  
  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      scaling_config[0].desired_size  # Allow manual/autoscaling adjustments
    ]
  }
}

# Outputs for verification
output "graviton_node_group_id" {
  description = "ID of the Graviton ARM64 node group"
  value       = aws_eks_node_group.graviton.id
}

output "graviton_node_group_status" {
  description = "Status of the Graviton ARM64 node group"
  value       = aws_eks_node_group.graviton.status
}

output "graviton_node_group_ami_type" {
  description = "AMI type used (should be AL2023_ARM_64_STANDARD)"
  value       = aws_eks_node_group.graviton.ami_type
}

output "graviton_instance_types" {
  description = "Instance types in use (should be t4g.medium)"
  value       = aws_eks_node_group.graviton.instance_types
}
