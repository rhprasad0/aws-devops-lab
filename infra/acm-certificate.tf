# ACM Certificate for TLS/HTTPS - Week 6 Option B
#
# WHAT: Creates an AWS Certificate Manager (ACM) certificate for our lab domain
# WHY: AWS ALB can only use ACM certificates (not cert-manager/Let's Encrypt)
#      This enables HTTPS for all services exposed via ALB Ingress
# HOW: Uses DNS validation via Route 53 for automatic certificate issuance
#
# SECURITY: 
# - Wildcard cert (*.dev.ryans-lab.click) covers all dev subdomains
# - DNS validation proves domain ownership without exposing HTTP endpoints
# - ACM handles automatic renewal (no manual intervention needed)
#
# COST: $0 (ACM certificates are free, only pay for Route 53 queries)
#
# LEARNING: This is "Option B" from Week 6 plan. Option A (cert-manager) doesn't
#           work with ALB because ALB requires ACM. cert-manager is still useful
#           for nginx-ingress or other non-AWS ingress controllers.

# Request ACM certificate for wildcard domain
# This covers: app.dev.ryans-lab.click, api.dev.ryans-lab.click, etc.
resource "aws_acm_certificate" "lab_wildcard" {
  domain_name       = "*.dev.ryans-lab.click"
  validation_method = "DNS"  # Prove ownership via Route 53 DNS records

  # Optional: Add apex domain if you want to use ryans-lab.click directly
  # subject_alternative_names = ["ryans-lab.click"]

  # BEST PRACTICE: Create new cert before destroying old one during updates
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "eks-lab-wildcard-cert"
    Environment = var.env
    Week        = "6"
    Purpose     = "ALB HTTPS termination"
  }
}

# Create Route 53 DNS validation records
# ACM requires you to prove domain ownership by creating specific DNS records
# Terraform automates this: ACM tells us what records to create, we create them
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.lab_wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true  # Safe to overwrite if record exists
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id  # References zone from external-dns-iam.tf
}

# Wait for certificate validation to complete
# This resource blocks until ACM confirms the certificate is issued
# Usually takes 1-5 minutes after DNS records propagate
resource "aws_acm_certificate_validation" "lab_wildcard" {
  certificate_arn         = aws_acm_certificate.lab_wildcard.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  # TIMEOUT: Give DNS propagation time (usually < 5 min, but allow up to 10)
  timeouts {
    create = "10m"
  }
}

# Output certificate ARN for use in Ingress annotations
output "acm_certificate_arn" {
  description = "ARN of ACM certificate for ALB HTTPS listeners"
  value       = aws_acm_certificate_validation.lab_wildcard.certificate_arn
}
