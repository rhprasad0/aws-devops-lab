# Agent2Agent Guestbook - DynamoDB Table
# Cost: ~$0.01-0.10/session (pay-per-request billing)
# This table stores guestbook messages with chronological indexing

resource "aws_dynamodb_table" "guestbook_messages" {
  count = var.enable_guestbook ? 1 : 0

  name         = var.guestbook_dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"  # No fixed costs, pay only for actual usage
  hash_key     = "message_id"
  range_key    = "timestamp"

  attribute {
    name = "message_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "entity_type"
    type = "S"
  }

  # GSI for chronological queries (list messages by timestamp)
  global_secondary_index {
    name            = "timestamp-index"
    hash_key        = "entity_type"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  # Disabled for ephemeral lab (saves costs, acceptable for dev)
  point_in_time_recovery {
    enabled = false
  }

  # Encryption at rest (AWS managed key, no extra cost)
  server_side_encryption {
    enabled = true
  }

  tags = {
    Name      = var.guestbook_dynamodb_table_name
    Component = "guestbook"
  }
}
