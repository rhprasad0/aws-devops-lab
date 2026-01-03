# AWS Fault Injection Simulator (FIS) - Week 15
#
# WHY use FIS?
# FIS lets you run controlled chaos experiments to test how your
# application handles infrastructure failures. This helps you:
# 1. Validate that PDBs work (pods reschedule correctly)
# 2. Test Karpenter's ability to provision replacement nodes
# 3. Verify application resilience during node failures
# 4. Build confidence in your disaster recovery procedures
#
# WHAT this experiment does:
# Terminates ONE EC2 instance from the EKS node group to simulate
# a node failure. The PDB should protect the guestbook app from
# going below 2 replicas during this disruption.
#
# COST: ~$0.01 per experiment run (FIS charges per action-minute)
# =============================================================================

# -----------------------------------------------------------------------------
# IAM Role for FIS
# FIS needs permission to terminate EC2 instances and write logs
# -----------------------------------------------------------------------------
resource "aws_iam_role" "fis" {
  name = "${var.env}-fis-experiment-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "FISAssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "fis.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:fis:${var.region}:${data.aws_caller_identity.current.account_id}:experiment/*"
        }
      }
    }]
  })

  tags = {
    Name      = "${var.env}-fis-experiment-role"
    Component = "chaos-engineering"
    Week      = "15"
  }
}

# Policy: Allow FIS to terminate EC2 instances
resource "aws_iam_role_policy" "fis_ec2_terminate" {
  name = "fis-ec2-terminate"
  role = aws_iam_role.fis.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEC2Terminate"
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances"
        ]
        # Restrict to instances with NodeType tag (set in launch template)
        # Note: provider default_tags don't propagate to EKS-created instances
        Resource = "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/NodeType" = "graviton-arm64"
          }
        }
      },
      {
        Sid    = "AllowEC2Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy: Allow FIS to write logs to CloudWatch
# checkov:skip=CKV_AWS_355:FIS log delivery requires broad CloudWatch Logs permissions
# checkov:skip=CKV_AWS_290:FIS log delivery follows AWS-recommended pattern
resource "aws_iam_role_policy" "fis_cloudwatch_logs" {
  name = "fis-cloudwatch-logs"
  role = aws_iam_role.fis.id

  # FIS requires these permissions to set up log delivery to CloudWatch Logs
  # See: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AWS-logs-infrastructure-CWL.html
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudWatchLogs"
      Effect = "Allow"
      Action = [
        "logs:CreateLogDelivery",
        "logs:PutResourcePolicy",
        "logs:DescribeLogGroups",
        "logs:DescribeResourcePolicies"
      ]
      Resource = "*"
    }]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for FIS Experiments
# Captures detailed experiment execution logs for debugging
# -----------------------------------------------------------------------------
# checkov:skip=CKV_AWS_338:Short retention intentional for ephemeral learning lab
# checkov:skip=CKV_AWS_158:KMS encryption adds cost; not needed for chaos logs
resource "aws_cloudwatch_log_group" "fis_experiments" {
  name              = "/aws/fis/${var.env}-experiments"
  retention_in_days = 7 # Short retention for cost savings

  tags = {
    Name      = "${var.env}-fis-experiments"
    Component = "chaos-engineering"
    Week      = "15"
  }
}

# -----------------------------------------------------------------------------
# FIS Experiment Template: Terminate Single EKS Node
# This simulates a node failure to test application resilience
# -----------------------------------------------------------------------------
resource "aws_fis_experiment_template" "terminate_eks_node" {
  description = "Terminate one EKS worker node to test application resilience and PDB effectiveness"
  role_arn    = aws_iam_role.fis.arn

  # Stop condition: none for now (experiment runs to completion)
  # In production, you'd use a CloudWatch alarm to auto-stop if SLOs are violated
  stop_condition {
    source = "none"
  }

  # Action: Terminate EC2 instances
  action {
    name        = "terminate-eks-node"
    action_id   = "aws:ec2:terminate-instances"
    description = "Terminate one EKS worker node"

    target {
      key   = "Instances"
      value = "eks-nodes"
    }
  }

  # Target: EKS worker nodes identified by tags
  target {
    name           = "eks-nodes"
    resource_type  = "aws:ec2:instance"
    selection_mode = "COUNT(1)" # Terminate only 1 node at a time

    # Target instances by NodeType tag (set in launch template tag_specifications)
    # Note: Provider default_tags don't propagate to EKS-created EC2 instances
    resource_tag {
      key   = "NodeType"
      value = "graviton-arm64"
    }

    # Only target running instances
    filter {
      path   = "State.Name"
      values = ["running"]
    }
  }

  # Log configuration for debugging
  log_configuration {
    log_schema_version = 2

    cloudwatch_logs_configuration {
      log_group_arn = "${aws_cloudwatch_log_group.fis_experiments.arn}:*"
    }
  }

  tags = {
    Name           = "${var.env}-terminate-eks-node"
    Component      = "chaos-engineering"
    Week           = "15"
    ExperimentType = "node-termination"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "fis_experiment_template_id" {
  description = "ID of the FIS experiment template"
  value       = aws_fis_experiment_template.terminate_eks_node.id
}

output "fis_role_arn" {
  description = "ARN of the FIS IAM role"
  value       = aws_iam_role.fis.arn
}

output "fis_log_group" {
  description = "CloudWatch Log Group for FIS experiments"
  value       = aws_cloudwatch_log_group.fis_experiments.name
}
