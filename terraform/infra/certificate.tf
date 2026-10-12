# Block 1: ask AWS for a free certificate for vote.springlaughing.dev,
# proven by a DNS record (not by email).
resource "aws_acm_certificate" "vote" {
  domain_name       = "vote.${var.domain_name}"
  validation_method = "DNS"
  tags              = { Name = "${var.name_prefix}-vote" }

  # If it ever has to be replaced, create the new one first: AWS refuses
  # to delete a certificate the load balancer is still using.
  lifecycle {
    create_before_destroy = true
  }
}

# Block 2: put the proof record AWS asks for into my Route 53 zone.
# AWS says which record it wants (name, type, value); Terraform creates it.
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for o in aws_acm_certificate.vote.domain_validation_options : o.domain_name => {
      name  = o.resource_record_name
      type  = o.resource_record_type
      value = o.resource_record_value
    }
  }

  zone_id         = aws_route53_zone.public.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.value]
  ttl             = 60
  allow_overwrite = true
}

# Block 3: wait until AWS has seen the record and issued the certificate.
# Only then does Terraform treat the certificate as ready to use.
resource "aws_acm_certificate_validation" "vote" {
  certificate_arn         = aws_acm_certificate.vote.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}