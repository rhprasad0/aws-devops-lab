# Security group for ALBs with VPC-restricted outbound access
# This follows security best practices by limiting ALB egress to VPC only

resource "aws_security_group" "alb" {
  name_prefix = "${var.env}-alb-"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for ALBs with VPC-restricted outbound access"

  tags = {
    Name = "${var.env}-alb-security-group"
  }
}

# Inbound rules: Allow HTTP from internet
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# Inbound rules: Allow HTTPS from internet  
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# Outbound rules: Restrict to VPC only (security best practice)
resource "aws_vpc_security_group_egress_rule" "alb_to_vpc" {
  security_group_id = aws_security_group.alb.id
  description       = "All traffic to VPC only"
  cidr_ipv4         = module.vpc.vpc_cidr_block
  ip_protocol       = "-1"  # all protocols
}

# Output the security group ID for use in ingress annotations
output "alb_security_group_id" {
  description = "Security group ID for ALBs with VPC-restricted outbound access"
  value       = aws_security_group.alb.id
}
