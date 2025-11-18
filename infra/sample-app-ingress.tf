# Sample app ingress managed by Terraform with ALB security group
#
# This creates a Kubernetes Ingress that triggers the AWS Load Balancer Controller
# to provision an Application Load Balancer (ALB) with our custom security group.
#
# Week 5 Update: Added hostname for ExternalDNS automatic Route 53 record creation
# ExternalDNS watches this Ingress and creates A record: app.dev.ryans-lab.click -> ALB
#
# Key security improvement: The ALB uses our custom security group that restricts
# outbound traffic to VPC only (10.0.0.0/16), following least privilege principles.

resource "kubernetes_ingress_v1" "sample_app" {
  depends_on = [helm_release.aws_load_balancer_controller]

  metadata {
    name      = "sample-app-ingress"
    namespace = "default"
    annotations = {
      # ALB Controller Configuration
      "alb.ingress.kubernetes.io/scheme"       = "internet-facing"  # Public ALB
      "alb.ingress.kubernetes.io/target-type" = "ip"               # Route directly to pod IPs
      
      # Security: Use our custom security group with VPC-restricted egress
      "alb.ingress.kubernetes.io/security-groups" = aws_security_group.alb.id
      
      # Health Check Configuration
      "alb.ingress.kubernetes.io/healthcheck-path"             = "/"
      "alb.ingress.kubernetes.io/healthcheck-interval-seconds" = "30"
      "alb.ingress.kubernetes.io/healthy-threshold-count"      = "2"
      "alb.ingress.kubernetes.io/unhealthy-threshold-count"    = "3"
      
      # Resource Tagging
      "alb.ingress.kubernetes.io/tags" = "Environment=dev,ManagedBy=aws-load-balancer-controller,Week=5"
    }
    labels = {
      app = "sample-app"
    }
  }

  spec {
    ingress_class_name = "alb"  # Use AWS Load Balancer Controller
    
    rule {
      # Week 5 Task 4: Add hostname for ExternalDNS
      # ExternalDNS automatically detects this hostname and creates Route 53 A record
      # pointing app.dev.ryans-lab.click to the ALB's DNS name
      host = "app.dev.ryans-lab.click"
      
      http {
        path {
          path      = "/"           # Match all paths
          path_type = "Prefix"      # Prefix matching (/* style)
          backend {
            service {
              name = "sample-app"   # Target the sample-app Service
              port {
                number = 80         # Service port
              }
            }
          }
        }
      }
    }
  }
}
