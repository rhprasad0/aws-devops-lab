# ECR Outputs for CI/CD workflows

output "ecr_repository_url" {
  description = "ECR repository URL for guestbook application"
  value       = aws_ecr_repository.guestbook.repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name"
  value       = aws_ecr_repository.guestbook.name
}

output "ecr_repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.guestbook.arn
}
