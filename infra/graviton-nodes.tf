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

# Launch template for Graviton nodes with prefix delegation support
# This enables max-pods=110 for t4g.medium instances with prefix delegation
#
# WHY THIS IS NEEDED:
# With prefix delegation enabled on VPC CNI, nodes can support more pods (110 vs 17)
# but the kubelet max-pods setting must also be increased. For AL2023, this is done
# via nodeadm configuration in user data.
resource "aws_launch_template" "graviton" {
  name_prefix = "${var.env}-graviton-"
  
  # User data for AL2023 using nodeadm configuration format
  # Sets max-pods=110 for prefix delegation support on t4g.medium
  # Reference: https://docs.aws.amazon.com/eks/latest/userguide/launch-templates.html
  user_data = base64encode(<<-EOF
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: application/node.eks.aws

---
apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  cluster:
    name: ${module.eks.cluster_name}
    apiServerEndpoint: ${module.eks.cluster_endpoint}
    certificateAuthority: ${module.eks.cluster_certificate_authority_data}
    cidr: ${module.eks.cluster_service_cidr}
  kubelet:
    config:
      maxPods: 110
    flags:
      - --max-pods=110

--BOUNDARY--
EOF
  )
  
  # Block device for root volume
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }
  
  # Metadata options for IMDSv2 (required for security)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }
  
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name      = "${var.env}-graviton-node"
      NodeType  = "graviton-arm64"
      Component = "compute"
    }
  }
  
  tags = {
    Name = "${var.env}-graviton-launch-template"
  }
  
  lifecycle {
    create_before_destroy = true
  }
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
  
  # Use launch template for custom max-pods with prefix delegation
  launch_template {
    id      = aws_launch_template.graviton.id
    version = aws_launch_template.graviton.latest_version
  }
  
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
    # NOTE: create_before_destroy doesn't work with EKS node groups
    # because node group names must be unique within a cluster.
    # EKS handles rolling updates internally when the launch template changes.
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
