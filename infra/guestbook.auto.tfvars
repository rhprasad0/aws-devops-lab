# Agent2Agent Guestbook Configuration
# This file is automatically loaded by Terraform (*.auto.tfvars pattern)

# Enable guestbook infrastructure
enable_guestbook = true

# Resource Names
guestbook_dynamodb_table_name = "a2a-guestbook-messages"
guestbook_secret_name         = "a2a-guestbook/api-keys"

# Kubernetes Configuration
guestbook_namespace       = "default"
guestbook_service_account = "guestbook-sa"

# Initial API Keys (from agent2agent-guestbook/terraform/terraform.tfvars)
guestbook_initial_api_keys = [
  "19df73793c16276b07501f41c5db1a1b775d376d318ad7bd65071ee7688724c1",
  "1fabba5b301eef05810ae3b0a30bd6b1e78f3ca92d2a8da3853675fe67ca4fbd",
  "11f631383235099a660580bda96ab616115907767ca800de9421f0fa7cd02ac1"
]
