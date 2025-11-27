# =============================================================================
# EBS CSI Driver for Kubernetes PersistentVolumes
# =============================================================================
# PURPOSE: Enables dynamic provisioning of AWS EBS volumes for Kubernetes PVCs
#
# HOW IT WORKS:
# 1. You create a PVC (PersistentVolumeClaim) requesting storage
# 2. CSI driver sees the request and calls AWS APIs to create an EBS volume
# 3. CSI driver creates a PV (PersistentVolume) and binds it to your PVC
# 4. CSI driver attaches the EBS volume to the node running your pod
# 5. Your pod mounts the volume at the specified path
#
# COST ESTIMATE (Option B - Full Observability Stack):
# - Prometheus: 5GB gp3 = ~$0.40/month
# - Grafana: 2GB gp3 = ~$0.16/month
# - Loki: 5GB gp3 = ~$0.40/month
# - Alertmanager: 1GB gp3 = ~$0.08/month
# - Jaeger: 2GB gp3 = ~$0.16/month
# - Total: ~15GB = ~$1.20/month
#
# SECURITY:
# - Uses EKS Pod Identity (only CSI pods get AWS permissions)
# - Volumes encrypted at rest with AWS-managed key
# - Least-privilege IAM via AWS managed policy
# =============================================================================

# -----------------------------------------------------------------------------
# IAM Role for EBS CSI Driver
# -----------------------------------------------------------------------------
# WHY: The CSI driver needs AWS permissions to create/attach/delete EBS volumes.
# We use EKS Pod Identity so only the CSI controller pods get these permissions,
# not all pods on the node (more secure than node IAM roles).

resource "aws_iam_role" "ebs_csi" {
  name = "${var.env}-ebs-csi-role"
  
  # Trust policy for EKS Pod Identity
  # This allows the EKS Pod Identity service to assume this role
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
          "sts:TagSession"  # Required for Pod Identity
        ]
      }
    ]
  })
  
  tags = {
    Name        = "${var.env}-ebs-csi-role"
    Description = "IAM role for EBS CSI driver to manage EBS volumes"
  }
}

# Attach the AWS managed policy for EBS CSI driver
# This policy includes least-privilege permissions:
# - ec2:CreateVolume, ec2:DeleteVolume
# - ec2:AttachVolume, ec2:DetachVolume
# - ec2:CreateSnapshot, ec2:DeleteSnapshot
# - ec2:DescribeVolumes, ec2:DescribeSnapshots, etc.
resource "aws_iam_role_policy_attachment" "ebs_csi" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi.name
}

# -----------------------------------------------------------------------------
# EKS Pod Identity Association
# -----------------------------------------------------------------------------
# WHY: This links the IAM role to the CSI controller's service account.
# When CSI controller pods start, they automatically get temporary AWS
# credentials for this role via the Pod Identity webhook.

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"  # Created by the addon
  role_arn        = aws_iam_role.ebs_csi.arn
  
  tags = {
    Name = "${var.env}-ebs-csi-pod-identity"
  }
}

# -----------------------------------------------------------------------------
# EBS CSI Driver EKS Addon
# -----------------------------------------------------------------------------
# WHY: Installing as an EKS-managed addon means:
# - AWS handles updates and security patches
# - Proper integration with EKS lifecycle
# - Less maintenance than self-managed Helm chart

resource "aws_eks_addon" "ebs_csi" {
  cluster_name = module.eks.cluster_name
  addon_name   = "aws-ebs-csi-driver"
  
  # Use most recent compatible version
  # You can pin to a specific version if needed: addon_version = "v1.28.0-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  
  # Ensure IAM role and Pod Identity are ready before installing
  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi,
    aws_eks_pod_identity_association.ebs_csi
  ]
  
  tags = {
    Name = "${var.env}-ebs-csi-addon"
  }
}

# -----------------------------------------------------------------------------
# gp3 StorageClass (Default)
# -----------------------------------------------------------------------------
# WHY: StorageClass defines HOW volumes are provisioned.
# gp3 is the cost-effective choice with good baseline performance.
#
# KEY SETTINGS EXPLAINED:
#
# volumeBindingMode: WaitForFirstConsumer
#   - Delays volume creation until a pod needs it
#   - Creates volume in the SAME AZ as the scheduled pod
#   - Prevents "volume is in us-east-1a but pod is in us-east-1b" errors
#
# reclaimPolicy: Delete
#   - When PVC is deleted, the EBS volume is automatically deleted
#   - Good for ephemeral/lab workloads (no orphaned volumes)
#   - For production data, you'd use "Retain" instead
#
# encrypted: true
#   - Encrypts volume data at rest using AWS-managed key (aws/ebs)
#   - No performance impact, security best practice
#   - For compliance, you'd use a customer-managed KMS key

resource "kubernetes_storage_class" "gp3" {
  depends_on = [aws_eks_addon.ebs_csi]
  
  metadata {
    name = "gp3"
    annotations = {
      # Make this the default StorageClass
      # PVCs without storageClassName will use this class
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true  # Can resize PVCs without recreating
  
  parameters = {
    type      = "gp3"
    encrypted = "true"
    # gp3 baseline performance (included in price):
    # - 3000 IOPS
    # - 125 MB/s throughput
    # Can be increased if needed (adds cost):
    # iops       = "3000"
    # throughput = "125"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "ebs_csi_role_arn" {
  description = "IAM role ARN for EBS CSI driver"
  value       = aws_iam_role.ebs_csi.arn
}

output "storage_class_name" {
  description = "Name of the default StorageClass for PVCs"
  value       = kubernetes_storage_class.gp3.metadata[0].name
}

