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

# Argo CD configuration
variable "enable_argocd" {
  description = "Enable Argo CD installation"
  type        = bool
  default     = true
}

# Argo CD applications (apply after cluster is ready)
variable "enable_argocd_apps" {
  description = "Enable Argo CD applications (requires cluster to be ready)"
  type        = bool
  default     = false
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

# Agent2Agent Guestbook configuration
variable "enable_guestbook" {
  description = "Enable Agent2Agent Guestbook infrastructure (DynamoDB + Secrets Manager)"
  type        = bool
  default     = true
}

variable "guestbook_dynamodb_table_name" {
  description = "Name of the DynamoDB table for guestbook messages"
  type        = string
  default     = "a2a-guestbook-messages"
}

variable "guestbook_secret_name" {
  description = "Name of the Secrets Manager secret for guestbook API keys"
  type        = string
  default     = "a2a-guestbook/api-keys"
}

variable "guestbook_initial_api_keys" {
  description = "Initial API keys to store in Secrets Manager"
  type        = list(string)
  default = [
    "dev-key-change-me",
    "test-key-change-me"
  ]
  sensitive = true
}

variable "guestbook_namespace" {
  description = "Kubernetes namespace for guestbook app"
  type        = string
  default     = "default"
}

variable "guestbook_service_account" {
  description = "Kubernetes ServiceAccount name for guestbook app"
  type        = string
  default     = "guestbook-sa"
}
