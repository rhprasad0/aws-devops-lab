# =============================================================================
# AWS Distro for OpenTelemetry (ADOT) - Week 10
# =============================================================================

# IAM Role for ADOT Collector (Pod Identity)
resource "aws_iam_role" "adot_collector" {
  count = var.enable_adot ? 1 : 0

  name = "${var.env}-adot-collector-role"

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
    Name = "${var.env}-adot-collector-role"
  }
}

resource "aws_iam_role_policy" "adot_prometheus" {
  count = var.enable_adot && var.enable_prometheus ? 1 : 0

  name = "${var.env}-adot-prometheus-policy"
  role = aws_iam_role.adot_collector[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:RemoteWrite",
          "aps:GetSeries",
          "aps:GetLabels",
          "aps:GetMetricMetadata"
        ]
        Resource = aws_prometheus_workspace.main[0].arn
      }
    ]
  })
}

# Associate Role with EKS Pod Identity
resource "aws_eks_pod_identity_association" "adot_collector" {
  count = var.enable_adot ? 1 : 0

  cluster_name    = module.eks.cluster_name
  namespace       = "opentelemetry-operator-system"
  service_account = "adot-collector"
  role_arn        = aws_iam_role.adot_collector[0].arn
}

# Generate Collector Manifest
# We use local_file to generate the YAML with the correct AMP endpoint
resource "local_file" "adot_collector_manifest" {
  count = var.enable_adot && var.enable_prometheus ? 1 : 0

  content = templatefile("${path.module}/templates/adot-collector.yaml.tpl", {
    AMP_ENDPOINT = "${aws_prometheus_workspace.main[0].prometheus_endpoint}api/v1/remote_write"
    REGION       = var.region
  })
  filename = "${path.module}/../k8s/adot/collector.yaml"
}

