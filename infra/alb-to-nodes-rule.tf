# Allow ALB to reach pods on port 80
# 
# WHAT: Security group rule allowing ALB to communicate with pods
# WHY: ALB health checks and traffic routing require access to pod port 80
# ISSUE: Node security group was missing ingress rule for ALB → pod communication
#
# This fixes the 504 Gateway Timeout by allowing the ALB security group
# to reach pods running on the EKS nodes on port 80 (HTTP traffic)

resource "aws_vpc_security_group_ingress_rule" "alb_to_nodes_http" {
  security_group_id = module.eks.node_security_group_id
  
  description                  = "ALB to pods HTTP traffic"
  from_port                   = 80
  to_port                     = 80
  ip_protocol                 = "tcp"
  referenced_security_group_id = aws_security_group.alb.id
  
  tags = {
    Name = "alb-to-nodes-http"
  }
}

# Optional: Also allow HTTPS traffic for future use
resource "aws_vpc_security_group_ingress_rule" "alb_to_nodes_https" {
  security_group_id = module.eks.node_security_group_id
  
  description                  = "ALB to pods HTTPS traffic"
  from_port                   = 443
  to_port                     = 443
  ip_protocol                 = "tcp"
  referenced_security_group_id = aws_security_group.alb.id
  
  tags = {
    Name = "alb-to-nodes-https"
  }
}
