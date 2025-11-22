# Agent2Agent Guestbook - Secrets Manager
# Cost: $0.40/month per secret
# Stores API keys for agent authentication

resource "aws_secretsmanager_secret" "guestbook_api_keys" {
  count = var.enable_guestbook ? 1 : 0

  name                    = var.guestbook_secret_name
  description             = "API keys for A2A Guestbook agents"
  recovery_window_in_days = 0  # Immediate deletion for ephemeral lab

  tags = {
    Name      = var.guestbook_secret_name
    Component = "guestbook"
  }
}

# Initial secret value with API keys from tfvars
resource "aws_secretsmanager_secret_version" "guestbook_api_keys" {
  count = var.enable_guestbook ? 1 : 0

  secret_id = aws_secretsmanager_secret.guestbook_api_keys[0].id
  secret_string = jsonencode({
    api_keys = var.guestbook_initial_api_keys
  })
}
