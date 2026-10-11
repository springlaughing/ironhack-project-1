# The public phone book for my domain. Porkbun points the domain here
# by listing this zone's 4 nameservers.
resource "aws_route53_zone" "public" {
  name    = var.domain_name
  comment = "Public names for the voting app"
  tags    = { Name = "${var.name_prefix}-zone" }
}