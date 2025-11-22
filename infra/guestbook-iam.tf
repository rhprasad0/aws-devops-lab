# Agent2Agent Guestbook - IAM for Pod Identity
# Uses EKS Pod Identity (successor to IRSA) for least-privilege access
# Allows guestbook pods to access only their DynamoDB table and secret

# IAM Role for guestbook pods
resource "aws_iam_role" "guestbook_pod" {
  count = var.enable_guestbook ? 1 : 0

  name = "${var.env}-guestbook-pod-role"

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
    Name      = "${var.env}-guestbook-pod-role"
    Component = "guestbook"
  }
}

# IAM Policy for DynamoDB access (least privilege)
resource "aws_iam_policy" "guestbook_dynamodb" {
  count = var.enable_guestbook ? 1 : 0

  name        = "${var.env}-guestbook-dynamodb-policy"
  description = "Allow guestbook pods to access their DynamoDB table"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.guestbook_messages[0].arn,
          "${aws_dynamodb_table.guestbook_messages[0].arn}/index/*"
        ]
      }
    ]
  })

  tags = {
    Name      = "${var.env}-guestbook-dynamodb-policy"
    Component = "guestbook"
  }
}

# IAM Policy for Secrets Manager access (least privilege)
resource "aws_iam_policy" "guestbook_secrets" {
  count = var.enable_guestbook ? 1 : 0

  name        = "${var.env}-guestbook-secrets-policy"
  description = "Allow guestbook pods to read their API keys secret"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.guestbook_api_keys[0].arn
      }
    ]
  })

  tags = {
    Name      = "${var.env}-guestbook-secrets-policy"
    Component = "guestbook"
  }
}

# Attach policies to role
resource "aws_iam_role_policy_attachment" "guestbook_dynamodb" {
  count = var.enable_guestbook ? 1 : 0

  role       = aws_iam_role.guestbook_pod[0].name
  policy_arn = aws_iam_policy.guestbook_dynamodb[0].arn
}

resource "aws_iam_role_policy_attachment" "guestbook_secrets" {
  count = var.enable_guestbook ? 1 : 0

  role       = aws_iam_role.guestbook_pod[0].name
  policy_arn = aws_iam_policy.guestbook_secrets[0].arn
}

# EKS Pod Identity Association
# Links the Kubernetes ServiceAccount to the IAM role
resource "aws_eks_pod_identity_association" "guestbook" {
  count = var.enable_guestbook ? 1 : 0

  cluster_name    = module.eks.cluster_name
  namespace       = var.guestbook_namespace
  service_account = var.guestbook_service_account
  role_arn        = aws_iam_role.guestbook_pod[0].arn

  tags = {
    Name      = "${var.env}-guestbook-pod-identity"
    Component = "guestbook"
  }
}
