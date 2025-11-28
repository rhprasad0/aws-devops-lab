# =============================================================================
# Amazon Managed Service for Prometheus (AMP) - Week 10 Observability
# =============================================================================
# PURPOSE: Managed Prometheus for metrics collection, storage, and querying
#
# WHY AMP INSTEAD OF SELF-HOSTED PROMETHEUS:
# 1. No cluster resources consumed - scraper runs outside EKS
# 2. Automatic scaling - handles any metric volume without tuning
# 3. High availability - built-in redundancy across AZs
# 4. Security - IAM-based access, encrypted at rest/transit
# 5. Cost-effective for lab - pay only for what you ingest
#
# HOW IT WORKS:
# 1. AMP Workspace stores metrics (like a managed Prometheus server)
# 2. Managed Scraper (agentless) discovers and scrapes metrics from EKS
# 3. Scraper sends metrics to workspace via AWS internal network
# 4. You query via Grafana or PromQL API
#
# ARCHITECTURE:
#   ┌─────────────┐     ┌─────────────────┐     ┌─────────────┐
#   │   EKS       │────▶│ Managed Scraper │────▶│ AMP         │
#   │   Cluster   │     │ (Agentless)     │     │ Workspace   │
#   └─────────────┘     └─────────────────┘     └─────────────┘
#         ▲                                           │
#         │                                           ▼
#   Pods export                                 ┌─────────────┐
#   /metrics                                    │  Grafana    │
#                                               │  (queries)  │
#                                               └─────────────┘
#
# COST ESTIMATE (Minimal Lab):
# - Metric ingestion: $0.90 per 10M samples (~$1-3/month for small cluster)
# - Storage: $0.03/GB-month (~$0.10-0.50/month)
# - Query: $0.10 per billion samples (~$0.01/month)
# - Scraper: Included (no additional charge)
# - TOTAL: ~$1-4/month (much cheaper than running Prometheus in-cluster!)
#
# RETENTION:
# - Default: 150 days (minimum, cannot be reduced)
# - This is fine for the lab - cost is primarily ingestion, not storage
#
# SECURITY:
# - Workspace encrypted with AWS-managed KMS key
# - Scraper uses IAM role with least-privilege EKS access
# - No credentials stored in cluster
# =============================================================================

# -----------------------------------------------------------------------------
# Enable/Disable Toggle
# -----------------------------------------------------------------------------
variable "enable_prometheus" {
  description = "Enable Amazon Managed Service for Prometheus"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# AMP Workspace
# -----------------------------------------------------------------------------
# This is the managed Prometheus "server" - stores metrics and handles queries.
# Think of it as a Prometheus backend without the hassle of running it yourself.

resource "aws_prometheus_workspace" "main" {
  count = var.enable_prometheus ? 1 : 0

  alias = "${var.env}-eks-metrics"

  # AWS-managed KMS encryption (free, secure, no key management needed)
  # For compliance requirements, you could use a customer-managed KMS key
  # kms_key_arn = aws_kms_key.prometheus.arn

  tags = {
    Name        = "${var.env}-amp-workspace"
    Description = "AMP workspace for EKS cluster metrics"
  }
}

# -----------------------------------------------------------------------------
# Default Scraper Configuration
# -----------------------------------------------------------------------------
# AWS provides a sensible default that scrapes common Kubernetes metrics:
# - Pod metrics (CPU, memory, network)
# - Node metrics (kubelet, cadvisor)
# - API server metrics
# - kube-state-metrics (if installed)
#
# This is a great starting point - you can customize later if needed.

data "aws_prometheus_default_scraper_configuration" "default" {
  count = var.enable_prometheus && var.enable_managed_scraper ? 1 : 0
}

# -----------------------------------------------------------------------------
# Managed Scraper (Agentless)
# -----------------------------------------------------------------------------
# KEY BENEFIT: No pods running in your cluster!
# AWS runs the scraper infrastructure and pulls metrics via ENIs.
#
# HOW IT CONNECTS:
# 1. AWS creates ENIs in your private subnets
# 2. Scraper uses these ENIs to reach pod /metrics endpoints
# 3. Uses IAM role (created automatically) to authenticate to EKS
# 4. Sends scraped metrics to AMP workspace via AWS internal network

resource "aws_prometheus_scraper" "eks" {
  count = var.enable_prometheus && var.enable_managed_scraper ? 1 : 0

  alias = "${var.env}-eks-scraper"

  # Source: Your EKS cluster
  source {
    eks {
      cluster_arn = module.eks.cluster_arn
      # Scraper needs access to at least 2 AZs for high availability
      subnet_ids = module.vpc.private_subnets
      # Optional: restrict which security groups the scraper can access
      # security_group_ids = [aws_security_group.scraper.id]
    }
  }

  # Destination: Your AMP workspace
  destination {
    amp {
      workspace_arn = aws_prometheus_workspace.main[0].arn
    }
  }

  # Use AWS default scrape configuration
  # This scrapes: pods, nodes, apiserver, kube-proxy, and kube-state-metrics
  scrape_configuration = data.aws_prometheus_default_scraper_configuration.default[0].configuration

  tags = {
    Name        = "${var.env}-amp-scraper"
    Description = "Managed scraper for EKS metrics collection"
  }

  # The scraper creates its own service-linked role automatically
  # AWS handles EKS access permissions for this role
  depends_on = [
    aws_prometheus_workspace.main
  ]
}

# -----------------------------------------------------------------------------
# EKS Access for Scraper (Automatic)
# -----------------------------------------------------------------------------
# NOTE: AWS automatically creates the EKS access entry for the managed scraper
# when we create the aws_prometheus_scraper resource. We don't need to manually
# create access entries for service-linked roles.
#
# The scraper's service-linked role automatically gets the 
# AmazonPrometheusScraperPolicy which allows:
# - List/watch pods, services, endpoints, nodes
# - Get /metrics from pods
#
# SECURITY NOTE: This grants read-only access to cluster resources.
# The scraper cannot modify anything in your cluster.

# Note: aws_caller_identity.current is defined in security.tf

# -----------------------------------------------------------------------------
# Recording Rules (Optional - Cost Optimization)
# -----------------------------------------------------------------------------
# Recording rules pre-compute frequently-used queries, which:
# 1. Speeds up dashboard loading
# 2. Can REDUCE costs by aggregating data before storage
#
# Example: Instead of storing raw CPU for every container,
# store pre-aggregated averages per deployment.

resource "aws_prometheus_rule_group_namespace" "recording_rules" {
  count = var.enable_prometheus ? 1 : 0

  name         = "recording-rules"
  workspace_id = aws_prometheus_workspace.main[0].id

  # Basic recording rules for common queries
  # These reduce query time and can help control costs
  data = <<-EOT
groups:
  - name: kubernetes-aggregate
    interval: 60s  # Evaluate every 60 seconds
    rules:
      # Average CPU by namespace (reduces cardinality)
      - record: namespace:container_cpu_usage_seconds_total:sum_rate
        expr: |
          sum by (namespace) (
            rate(container_cpu_usage_seconds_total{container!=""}[5m])
          )
      
      # Average memory by namespace
      - record: namespace:container_memory_working_set_bytes:sum
        expr: |
          sum by (namespace) (
            container_memory_working_set_bytes{container!=""}
          )
      
      # Pod restart rate (useful for health monitoring)
      - record: namespace:kube_pod_container_status_restarts_total:increase1h
        expr: |
          sum by (namespace) (
            increase(kube_pod_container_status_restarts_total[1h])
          )
EOT

  tags = {
    Name        = "${var.env}-prometheus-recording-rules"
    Description = "Pre-computed metrics for faster queries"
  }
}

# -----------------------------------------------------------------------------
# Alerting Rules (Optional - Week 10 stretch goal)
# -----------------------------------------------------------------------------
# Native AMP alerting sends alerts to SNS (no AlertManager needed!)
# We'll add this in a follow-up if you want to set up alerts.

# resource "aws_prometheus_alert_manager_definition" "main" {
#   count        = var.enable_prometheus ? 1 : 0
#   workspace_id = aws_prometheus_workspace.main[0].id
#   
#   definition = <<-EOT
# alertmanager_config: |
#   route:
#     receiver: 'default'
#   receivers:
#     - name: 'default'
#       sns_configs:
#         - topic_arn: '${aws_sns_topic.alerts.arn}'
#           sigv4:
#             region: '${var.region}'
# EOT
# }

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "amp_workspace_id" {
  description = "AMP Workspace ID"
  value       = var.enable_prometheus ? aws_prometheus_workspace.main[0].id : null
}

output "amp_workspace_arn" {
  description = "AMP Workspace ARN (for Grafana data source configuration)"
  value       = var.enable_prometheus ? aws_prometheus_workspace.main[0].arn : null
}

output "amp_prometheus_endpoint" {
  description = "Prometheus-compatible endpoint for queries"
  value       = var.enable_prometheus ? aws_prometheus_workspace.main[0].prometheus_endpoint : null
}

output "amp_remote_write_url" {
  description = "Remote write URL (for additional metric sources)"
  value       = var.enable_prometheus ? "${aws_prometheus_workspace.main[0].prometheus_endpoint}api/v1/remote_write" : null
}

output "amp_query_url" {
  description = "Query URL for Grafana data source"
  value       = var.enable_prometheus ? "${aws_prometheus_workspace.main[0].prometheus_endpoint}api/v1/query" : null
}

