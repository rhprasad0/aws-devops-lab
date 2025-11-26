# GitHub OIDC Provider for GitHub Actions
# Week 8: CI/CD Part 1 - Secure authentication without long-lived credentials
# Cost: $0 (IAM is free)

# GitHub's OIDC provider
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  # GitHub's OIDC thumbprint (verified)
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = {
    Name = "github-actions-oidc"
  }
}

# IAM role for GitHub Actions to push to ECR
resource "aws_iam_role" "github_actions_ecr" {
  name = "${var.env}-github-actions-ecr-role"

  # Trust policy: allow GitHub Actions from your repos to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Allow both repos: app repo (CI/CD) and infra repo (validation)
            "token.actions.githubusercontent.com:sub" = [
              "repo:rhprasad0/agent2agent-guestbook:*",
              "repo:rhprasad0/aws-devops-lab:*"
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name = "github-actions-ecr-role"
  }
}

# Policy: ECR push permissions
resource "aws_iam_role_policy" "github_actions_ecr_push" {
  name = "ecr-push-policy"
  role = aws_iam_role.github_actions_ecr.id

  # Least-privilege: only what's needed to push images
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          # Push permissions (for CI/CD pipeline)
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          # Read permissions (for image validation workflow)
          "ecr:DescribeImages",
        ]
        Resource = aws_ecr_repository.guestbook.arn
      }
    ]
  })
}
