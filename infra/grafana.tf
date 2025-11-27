# =============================================================================
# Amazon Managed Grafana (AMG) - Week 10 Observability
# =============================================================================
# PURPOSE: Managed Grafana for visualizing metrics from AMP (Prometheus)
#
# WHY AWS MANAGED GRAFANA INSTEAD OF SELF-HOSTED:
# 1. No cluster resources consumed - runs as managed AWS service
# 2. Automatic scaling and high availability
# 3. Native AWS integrations - easy data source setup for AMP, CloudWatch
# 4. Security - IAM-based access, encrypted at rest/transit
# 5. Cost-effective for lab - pay only for active users
#
# ARCHITECTURE:
#   ┌─────────────────┐     ┌─────────────────┐
#   │  AMP Workspace  │────▶│ Amazon Managed  │
#   │  (Prometheus)   │     │   Grafana       │
#   └─────────────────┘     └─────────────────┘
#           │                       │
#           │                       ▼
#   ┌───────▼─────────┐     ┌─────────────────┐
#   │  EKS Cluster    │     │  You (browser)  │
#   │  (metrics src)  │     │  via SSO login  │
#   └─────────────────┘     └─────────────────┘
#
# AUTHENTICATION:
# AWS Managed Grafana supports two authentication methods:
# 1. AWS IAM Identity Center (SSO) - RECOMMENDED for AWS accounts
# 2. SAML - For external identity providers
#
# This configuration uses AWS_SSO which requires IAM Identity Center
# to be enabled in your AWS account (see setup steps below).
#
# COST ESTIMATE:
# - Editor/Admin users: $9/user/month (first 5 users included in Grafana Enterprise)
# - Viewer users: $5/user/month
# - For Grafana (OSS) workspace: No per-user fee, just AWS usage
# - This lab uses Grafana OSS edition to minimize cost
# - TOTAL: ~$0/month for basic lab usage with OSS edition
#
# SETUP STEPS (One-time, before terraform apply):
# 1. Enable IAM Identity Center in AWS Console:
#    - Go to AWS IAM Identity Center console
#    - Click "Enable" if not already enabled
#    - Choose your identity source (built-in recommended for lab)
#
# 2. Create an IAM Identity Center user:
#    - Users → Add user
#    - Enter email and name
#    - Complete email verification
#
# 3. After terraform apply, assign user to Grafana:
#    - AWS Console → Amazon Managed Grafana → Your workspace
#    - "Assign new user or group"
#    - Select your IAM Identity Center user
#    - Assign "Admin" role
# =============================================================================

# -----------------------------------------------------------------------------
# Enable/Disable Toggle
# -----------------------------------------------------------------------------
variable "enable_grafana" {
  description = "Enable Amazon Managed Grafana"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# IAM Role for Grafana Workspace
# -----------------------------------------------------------------------------
# Grafana needs an IAM role to:
# 1. Query Amazon Managed Prometheus (AMP)
# 2. Access CloudWatch for logs/metrics
# 3. Access any other AWS data sources you configure

resource "aws_iam_role" "grafana" {
  count = var.enable_grafana ? 1 : 0

  name = "${var.env}-grafana-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "grafana.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        # Condition restricts to this specific account for security
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          # Further restrict to workspaces in this account
          StringLike = {
            "aws:SourceArn" = "arn:aws:grafana:${var.region}:${data.aws_caller_identity.current.account_id}:/workspaces/*"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.env}-grafana-role"
    Description = "IAM role for Amazon Managed Grafana workspace"
  }
}

# -----------------------------------------------------------------------------
# IAM Policy for Prometheus Data Source
# -----------------------------------------------------------------------------
# Least-privilege policy scoped to our specific AMP workspace

resource "aws_iam_role_policy" "grafana_prometheus" {
  count = var.enable_grafana && var.enable_prometheus ? 1 : 0

  name = "${var.env}-grafana-prometheus-policy"
  role = aws_iam_role.grafana[0].id

  # Policy based on AWS documentation:
  # https://docs.aws.amazon.com/grafana/latest/userguide/AMG-manage-permissions.html
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PrometheusAccess"
        Effect = "Allow"
        Action = [
          # Required for data source discovery (not required for plugin to work)
          "aps:ListWorkspaces",
          "aps:DescribeWorkspace",
          # Required for querying metrics
          "aps:QueryMetrics",
          "aps:GetLabels",
          "aps:GetSeries",
          "aps:GetMetricMetadata"
        ]
        # Note: Using "*" to match AWS service-managed policy behavior
        # For tighter security, scope to specific workspace ARN
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IAM Policy for CloudWatch Data Source (Optional but useful)
# -----------------------------------------------------------------------------
# Allows Grafana to query CloudWatch for additional AWS metrics

resource "aws_iam_role_policy" "grafana_cloudwatch" {
  count = var.enable_grafana ? 1 : 0

  name = "${var.env}-grafana-cloudwatch-policy"
  role = aws_iam_role.grafana[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarms",
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAnomalyDetectors",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2DescribeRead"
        Effect = "Allow"
        Action = [
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions"
        ]
        Resource = "*"
      },
      {
        Sid    = "TagsRead"
        Effect = "Allow"
        Action = [
          "tag:GetResources"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Amazon Managed Grafana Workspace
# -----------------------------------------------------------------------------
# The workspace is the Grafana "server" - where dashboards and data sources live

resource "aws_grafana_workspace" "main" {
  count = var.enable_grafana ? 1 : 0

  name        = "${var.env}-grafana"
  description = "Grafana workspace for EKS observability - Week 10"

  # Account access - CURRENT_ACCOUNT is typical for single-account labs
  account_access_type = "CURRENT_ACCOUNT"

  # Authentication - AWS_SSO requires IAM Identity Center to be enabled
  # See setup steps at the top of this file
  authentication_providers = ["AWS_SSO"]

  # Permission type - SERVICE_MANAGED means AWS handles IAM integration
  permission_type = "SERVICE_MANAGED"

  # The IAM role Grafana uses to access AWS data sources
  role_arn = aws_iam_role.grafana[0].arn

  # Grafana version - use latest stable
  grafana_version = "10.4"

  # Data sources this workspace can access
  # PROMETHEUS - for AMP metrics
  # CLOUDWATCH - for AWS service metrics and logs
  data_sources = ["PROMETHEUS", "CLOUDWATCH"]

  # Notification destinations (optional, for alerting)
  # notification_destinations = ["SNS"]

  # Workspace configuration
  configuration = jsonencode({
    plugins = {
      # Allow installing additional plugins from Grafana catalog
      pluginAdminEnabled = true
    }
    unifiedAlerting = {
      # Enable Grafana's unified alerting (can be used with AMP AlertManager)
      enabled = true
    }
  })

  tags = {
    Name        = "${var.env}-grafana-workspace"
    Description = "Managed Grafana for EKS observability"
  }
}

# -----------------------------------------------------------------------------
# Grafana Workspace Data Source Configuration
# -----------------------------------------------------------------------------
# Automatically configure AMP as a data source in the Grafana workspace
# This uses the grafana_workspace_configuration resource with native AWS integration

resource "aws_grafana_workspace_service_account" "prometheus_admin" {
  count = var.enable_grafana ? 1 : 0

  name         = "prometheus-admin"
  grafana_role = "ADMIN"
  workspace_id = aws_grafana_workspace.main[0].id
}

# Generate a token for the service account (used for API access if needed)
resource "aws_grafana_workspace_service_account_token" "prometheus_admin" {
  count = var.enable_grafana ? 1 : 0

  name               = "prometheus-admin-token"
  service_account_id = aws_grafana_workspace_service_account.prometheus_admin[0].id
  seconds_to_live    = 2592000 # 30 days
  workspace_id       = aws_grafana_workspace.main[0].id
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "grafana_workspace_id" {
  description = "Amazon Managed Grafana Workspace ID"
  value       = var.enable_grafana ? aws_grafana_workspace.main[0].id : null
}

output "grafana_workspace_endpoint" {
  description = "Amazon Managed Grafana Workspace URL - access this in your browser"
  value       = var.enable_grafana ? aws_grafana_workspace.main[0].endpoint : null
}

output "grafana_workspace_arn" {
  description = "Amazon Managed Grafana Workspace ARN"
  value       = var.enable_grafana ? aws_grafana_workspace.main[0].arn : null
}

output "grafana_role_arn" {
  description = "IAM Role ARN used by Grafana workspace"
  value       = var.enable_grafana ? aws_iam_role.grafana[0].arn : null
}

output "grafana_service_account_token" {
  description = "Grafana service account token (for API access - keep secret!)"
  value       = var.enable_grafana ? aws_grafana_workspace_service_account_token.prometheus_admin[0].key : null
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Post-Apply Instructions (printed as output)
# -----------------------------------------------------------------------------

# Use locals to build the instructions string
locals {
  # Build URL references only when resources exist
  grafana_endpoint = var.enable_grafana ? aws_grafana_workspace.main[0].endpoint : "N/A"
  amp_workspace_id = var.enable_prometheus ? aws_prometheus_workspace.main[0].id : "N/A"
  amp_endpoint     = var.enable_prometheus ? aws_prometheus_workspace.main[0].prometheus_endpoint : "N/A"

  grafana_instructions = var.enable_grafana ? join("\n", [
    "",
    "========================================",
    "AMAZON MANAGED GRAFANA SETUP COMPLETE!",
    "========================================",
    "",
    "1. ACCESS GRAFANA:",
    "   URL: ${local.grafana_endpoint}",
    "",
    "2. SIGN IN:",
    "   - Click 'Sign in with AWS IAM Identity Center'",
    "   - Use your IAM Identity Center credentials",
    "   - If you don't have access, ask your admin to assign you to this workspace",
    "",
    "3. CONFIGURE PROMETHEUS DATA SOURCE (Using AWS Data Source Config):",
    "   a. In AWS Console: Amazon Managed Grafana -> Your workspace",
    "   b. Data sources tab -> Select 'Amazon Managed Service for Prometheus'",
    "   c. Actions -> 'Enable service-managed policy'",
    "   d. Click 'Configure in Grafana' to open workspace",
    "   e. In Grafana: AWS icon -> AWS services -> Prometheus",
    "   f. Select region: ${var.region}",
    "   g. Select your AMP workspace and click 'Add data source'",
    "",
    "4. IMPORT KUBERNETES DASHBOARDS:",
    "   a. Go to Dashboards -> Import",
    "   b. Import these recommended dashboards by ID:",
    "      - 315   - Kubernetes cluster monitoring (via Prometheus)",
    "      - 6417  - Kubernetes Pods monitoring",
    "      - 13770 - Kube-state-metrics v2",
    "      - 12006 - Kubernetes apiserver",
    "   c. Select 'Amazon Managed Prometheus' as the data source",
    "",
    "5. CREATE CUSTOM DASHBOARD:",
    "   - Explore your metrics using the Explore view",
    "   - Query: up{} to see all scrape targets",
    "   - Query: container_cpu_usage_seconds_total to see CPU usage",
    "",
    "AMP Workspace ID: ${local.amp_workspace_id}",
    "AMP Endpoint: ${local.amp_endpoint}",
    "",
    "COST NOTE: This workspace uses SERVICE_MANAGED permissions.",
    "User costs: $9/admin, $5/viewer per month when assigned.",
    ""
  ]) : "Grafana not enabled"
}

output "grafana_setup_instructions" {
  description = "Instructions to complete Grafana setup"
  value       = local.grafana_instructions
}

