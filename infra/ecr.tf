# ECR Repository for Guestbook Application
# Week 8: CI/CD Part 1 - Container Registry
# Cost: ~$0.10/GB/month storage

resource "aws_ecr_repository" "guestbook" {
  name                 = "eks-lab/guestbook"
  image_tag_mutability = "MUTABLE"  # Allow overwriting tags for dev

  image_scanning_configuration {
    scan_on_push = true  # Security: scan images for vulnerabilities
  }

  encryption_configuration {
    encryption_type = "AES256"  # Default encryption (no KMS cost)
  }

  tags = {
    Name        = "guestbook-ecr"
    Application = "guestbook"
  }
}

# Lifecycle policy: keep last 5 images to control costs
resource "aws_ecr_lifecycle_policy" "guestbook" {
  repository = aws_ecr_repository.guestbook.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
