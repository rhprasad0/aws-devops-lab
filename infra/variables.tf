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
