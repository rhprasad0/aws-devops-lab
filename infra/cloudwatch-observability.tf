# CloudWatch Observability EKS Add-on (Week 11)
# Provides: Fluent Bit for logs, CloudWatch Agent for metrics, Container Insights
# This replaces manual Fluent Bit installation with AWS-managed add-on

# IAM Role for CloudWatch Agent (using EKS Pod Identity)
resource "aws_iam_role" "cloudwatch_observability" {
  name = "${var.env}-cloudwatch-observability"
  
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
    Name = "${var.env}-cloudwatch-observability"
  }
}

# Attach AWS managed policy for CloudWatch Agent
resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server_policy" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.cloudwatch_observability.name
}

# Additional permissions for X-Ray (tracing - Week 11 Part 2)
resource "aws_iam_role_policy_attachment" "xray_daemon_write_access" {
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
  role       = aws_iam_role.cloudwatch_observability.name
}

# EKS Pod Identity Association for CloudWatch Agent
resource "aws_eks_pod_identity_association" "cloudwatch_agent" {
  cluster_name    = module.eks.cluster_name
  namespace       = "amazon-cloudwatch"
  service_account = "cloudwatch-agent"
  role_arn        = aws_iam_role.cloudwatch_observability.arn
}

# CloudWatch Observability EKS Add-on
# Installs: CloudWatch Agent + Fluent Bit + Container Insights
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name = module.eks.cluster_name
  addon_name   = "amazon-cloudwatch-observability"
  
  # Use latest stable version for EKS 1.32
  addon_version = "v4.7.0-eksbuild.1"
  
  # Resolve conflicts by overwriting (add-on takes precedence)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  
  # Configuration to customize the add-on behavior
  configuration_values = jsonencode({
    agent = {
      config = {
        logs = {
          metrics_collected = {
            # Enable Container Insights metrics
            kubernetes = {
              enhanced_container_insights = true
            }
          }
        }
      }
    }
    # Fluent Bit configuration for log collection
    containerLogs = {
      enabled = true
    }
  })
  
  depends_on = [
    aws_eks_pod_identity_association.cloudwatch_agent,
    aws_iam_role_policy_attachment.cloudwatch_agent_server_policy,
    module.eks
  ]
  
  tags = {
    Name = "${var.env}-cloudwatch-observability"
  }
}

# Output the log group names for reference
output "cloudwatch_log_groups" {
  description = "CloudWatch Log Groups created by Container Insights"
  value = {
    application = "/aws/containerinsights/${module.eks.cluster_name}/application"
    host        = "/aws/containerinsights/${module.eks.cluster_name}/host"
    dataplane   = "/aws/containerinsights/${module.eks.cluster_name}/dataplane"
    performance = "/aws/containerinsights/${module.eks.cluster_name}/performance"
  }
}

