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
