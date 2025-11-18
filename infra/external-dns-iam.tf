# ExternalDNS IAM Role - Week 5 Task 2
#
# Creates IAM role with least-privilege Route 53 permissions
# Based on AWS EKS Community Add-ons documentation
# Scoped to only the ryans-lab.click hosted zone for security

# Data source for existing hosted zone
data "aws_route53_zone" "main" {
  name = "ryans-lab.click"
}

# IAM policy - minimal permissions per AWS docs
resource "aws_iam_policy" "external_dns" {
  name        = "${var.env}-external-dns-policy"
  description = "ExternalDNS policy for ryans-lab.click zone"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = data.aws_route53_zone.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM role for ExternalDNS using Pod Identity
resource "aws_iam_role" "external_dns" {
  name = "${var.env}-external-dns-role"

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
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}
