# CloudWatch Observability EKS Add-on (Week 11)
# Provides: Fluent Bit for logs, CloudWatch Agent for metrics, Container Insights, X-Ray tracing
# This replaces manual Fluent Bit installation with AWS-managed add-on
#
# X-Ray Tracing Setup:
# - The CloudWatch Agent includes an OTLP receiver for traces
# - Applications send traces via OTLP protocol to the agent
# - Agent forwards traces to AWS X-Ray
# - No separate ADOT Collector needed!

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
  # Enables: Container Insights (metrics), Fluent Bit (logs), and X-Ray (traces)
  #
  # X-Ray Tracing:
  # - OTLP receivers configured to listen on 0.0.0.0 (all interfaces)
  # - Since agent uses hostNetwork, apps can send traces to NODE_IP:4317 or NODE_IP:4318
  # - The K8s service cloudwatch-agent.amazon-cloudwatch also routes to these ports
  # - Agent forwards traces to AWS X-Ray
  configuration_values = jsonencode({
    agent = {
      config = {
        # Logs section: Container Insights metrics
        logs = {
          metrics_collected = {
            kubernetes = {
              enhanced_container_insights = true
            }
          }
        }
        # Traces section: Enable X-Ray tracing with OTLP receivers
        # Bind to 0.0.0.0 to accept traces from other pods
        traces = {
          traces_collected = {
            xray = {
              bind_address = "0.0.0.0:2000"
              tcp_proxy = {
                bind_address = "0.0.0.0:2000"
              }
            }
            otlp = {
              grpc_endpoint = "0.0.0.0:4317"
              http_endpoint = "0.0.0.0:4318"
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
    aws_iam_role_policy_attachment.xray_daemon_write_access,
    module.eks
  ]

  tags = {
    Name = "${var.env}-cloudwatch-observability"
  }
}

# =============================================================================
# Log Retention Configuration (Week 11 Security)
# =============================================================================
# Container Insights creates log groups automatically. We manage retention
# separately to control costs and comply with security requirements.
# Retention: 7 days balances cost with incident investigation needs.

resource "aws_cloudwatch_log_group" "container_insights_application" {
  name              = "/aws/containerinsights/${module.eks.cluster_name}/application"
  retention_in_days = 7

  tags = {
    Name = "container-insights-application"
  }
}

resource "aws_cloudwatch_log_group" "container_insights_dataplane" {
  name              = "/aws/containerinsights/${module.eks.cluster_name}/dataplane"
  retention_in_days = 7

  tags = {
    Name = "container-insights-dataplane"
  }
}

resource "aws_cloudwatch_log_group" "container_insights_host" {
  name              = "/aws/containerinsights/${module.eks.cluster_name}/host"
  retention_in_days = 7

  tags = {
    Name = "container-insights-host"
  }
}

resource "aws_cloudwatch_log_group" "container_insights_performance" {
  name              = "/aws/containerinsights/${module.eks.cluster_name}/performance"
  retention_in_days = 7

  tags = {
    Name = "container-insights-performance"
  }
}

# Output the log group names for reference
output "cloudwatch_log_groups" {
  description = "CloudWatch Log Groups created by Container Insights"
  value = {
    application = aws_cloudwatch_log_group.container_insights_application.name
    host        = aws_cloudwatch_log_group.container_insights_host.name
    dataplane   = aws_cloudwatch_log_group.container_insights_dataplane.name
    performance = aws_cloudwatch_log_group.container_insights_performance.name
  }
}

# Output X-Ray tracing endpoints for application configuration
output "xray_otlp_endpoints" {
  description = "OTLP endpoints for sending traces to X-Ray via CloudWatch Agent"
  value = {
    grpc = "http://cloudwatch-agent.amazon-cloudwatch:4317"
    http = "http://cloudwatch-agent.amazon-cloudwatch:4318"
  }
}


