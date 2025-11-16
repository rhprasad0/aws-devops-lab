# Security Baseline Services for Week 0
# Cost: ~$3-5/month for minimal usage

# 1. GuardDuty - Enable first (threat detection)
resource "aws_guardduty_detector" "main" {
  enable = true

  tags = {
    Name = "eks-lab-guardduty"
  }
}

# GuardDuty Features (replaces deprecated datasources block)
resource "aws_guardduty_detector_feature" "s3_logs" {
  detector_id = aws_guardduty_detector.main.id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "eks_audit_logs" {
  detector_id = aws_guardduty_detector.main.id
  name        = "EKS_AUDIT_LOGS"
  status      = "ENABLED"  # Enable for EKS monitoring
}

# Disable EBS malware protection to control costs (~$1/GB scanned)
resource "aws_guardduty_detector_feature" "ebs_malware_protection" {
  detector_id = aws_guardduty_detector.main.id
  name        = "EBS_MALWARE_PROTECTION"
  status      = "DISABLED"
}

# 2. Config - Enable second (compliance monitoring)
# Create service-linked role for Config first
resource "aws_iam_service_linked_role" "config" {
  aws_service_name = "config.amazonaws.com"
}

# Configuration recorder (defines what to record)
resource "aws_config_configuration_recorder" "main" {
  name     = "eks-lab-config"
  role_arn = aws_iam_service_linked_role.config.arn

  recording_group {
    all_supported                 = false
    include_global_resource_types = false
    
    # Monitor only essential resources for cost control
    resource_types = [
      "AWS::S3::Bucket",
      "AWS::EC2::SecurityGroup",
      "AWS::IAM::Role",
      "AWS::IAM::Policy",
      "AWS::EKS::Cluster"
    ]
  }

  recording_mode {
    recording_frequency = "DAILY"  # Reduce from CONTINUOUS to save costs
  }

  depends_on = [aws_iam_service_linked_role.config]
}

# Config delivery channel (defines where to store)
resource "aws_config_delivery_channel" "main" {
  name           = "eks-lab-config"
  s3_bucket_name = aws_s3_bucket.config.bucket

  depends_on = [
    aws_s3_bucket_policy.config,
    aws_config_configuration_recorder.main
  ]
}

# Enable the configuration recorder (requires both recorder and delivery channel)
resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  
  depends_on = [
    aws_config_configuration_recorder.main,
    aws_config_delivery_channel.main
  ]
}

# S3 bucket for Config
resource "aws_s3_bucket" "config" {
  bucket        = "${var.owner}-eks-lab-config-${random_id.bucket_suffix.hex}"
  force_destroy = true  # Allow destroy for ephemeral lab
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket policy for Config
resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketExistenceCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.config.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Random suffix for unique bucket names
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Data source for account ID
data "aws_caller_identity" "current" {}

# 3. Security Hub - Enable last (aggregates findings from GuardDuty and Config)
resource "aws_securityhub_account" "main" {
  enable_default_standards = true

  depends_on = [
    aws_guardduty_detector.main,
    aws_config_configuration_recorder.main
  ]
}
