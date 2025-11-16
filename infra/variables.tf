variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Resource owner"
  type        = string
  default     = "ryan"
}

variable "ttl_hours" {
  description = "Time to live in hours"
  type        = string
  default     = "24"
}

# Tailscale configuration
variable "enable_tailscale" {
  description = "Enable Tailscale gateway instance"
  type        = bool
  default     = false
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key (set via TF_VAR_tailscale_auth_key)"
  type        = string
  default     = ""
  sensitive   = true
}

# EKS endpoint security
variable "eks_private_only" {
  description = "Disable public EKS endpoint (Tailscale access only)"
  type        = bool
  default     = false
}
