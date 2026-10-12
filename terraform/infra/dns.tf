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

# vote.springlaughing.dev → the load balancer.
resource "aws_route53_record" "vote" {
  zone_id = aws_route53_zone.public.zone_id
  name    = "vote.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = false
  }
}

# Private zone: these names only exist inside my VPC.
resource "aws_route53_zone" "internal" {
  name    = "voting.internal"
  comment = "Private names for the voting app servers"

  vpc {
    vpc_id = aws_vpc.main.id # attaching a VPC is what makes the zone private
  }

  tags = { Name = "${var.name_prefix}-internal" }
}

# Which name points where. Step 2: everything lives on C1.
locals {
  internal_names = {
    "redis-a"   = aws_instance.c1.private_ip
    "db-write"  = aws_instance.c1.private_ip
    "db-read-a" = aws_instance.c1.private_ip
  }
}

# One A record per name: "redis-a.voting.internal is 10.0.20.68"
resource "aws_route53_record" "internal" {
  for_each = local.internal_names

  zone_id = aws_route53_zone.internal.zone_id
  name    = "${each.key}.${aws_route53_zone.internal.name}"
  type    = "A"   # A record = name → IPv4 address
  ttl     = 60    # servers may remember the answer for 60 seconds, so a change takes effect within a minute
  records = [each.value]
}