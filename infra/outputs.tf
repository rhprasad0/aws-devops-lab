output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

# EKS Outputs
output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "EKS cluster version"
  value       = module.eks.cluster_version
}

# Tailscale outputs
output "tailscale_subnet_router_id" {
  description = "Tailscale subnet router instance ID"
  value       = var.enable_tailscale ? aws_instance.tailscale[0].id : null
}

output "tailscale_subnet_router_ip" {
  description = "Tailscale subnet router private IP"
  value       = var.enable_tailscale ? aws_instance.tailscale[0].private_ip : null
}

# Agent2Agent Guestbook outputs
output "guestbook_dynamodb_table_name" {
  description = "Name of the guestbook DynamoDB table"
  value       = var.enable_guestbook ? aws_dynamodb_table.guestbook_messages[0].name : null
}

output "guestbook_dynamodb_table_arn" {
  description = "ARN of the guestbook DynamoDB table"
  value       = var.enable_guestbook ? aws_dynamodb_table.guestbook_messages[0].arn : null
}

output "guestbook_secret_name" {
  description = "Name of the guestbook Secrets Manager secret"
  value       = var.enable_guestbook ? aws_secretsmanager_secret.guestbook_api_keys[0].name : null
}

output "guestbook_secret_arn" {
  description = "ARN of the guestbook Secrets Manager secret"
  value       = var.enable_guestbook ? aws_secretsmanager_secret.guestbook_api_keys[0].arn : null
}

output "guestbook_pod_role_arn" {
  description = "IAM role ARN for guestbook pods (Pod Identity)"
  value       = var.enable_guestbook ? aws_iam_role.guestbook_pod[0].arn : null
}

# GitHub Actions outputs
output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions to push to ECR"
  value       = aws_iam_role.github_actions_ecr.arn
}
