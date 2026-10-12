# Take over the zone that already exists (it survived the cleanup on 11 Oct),
# so its 4 name servers, set at Porkbun, stay the same.
import {
  to = aws_route53_zone.public
  id = "Z066212434QWDCZKINVKU"
}

# The public phone book for my domain. Porkbun points the domain here
# by listing this zone's 4 nameservers.
resource "aws_route53_zone" "public" {
  name    = var.domain_name
  comment = "Public names for the voting app"
  tags    = { Name = "${var.name_prefix}-zone" }
}