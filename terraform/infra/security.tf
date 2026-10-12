# Firewall rules by role: every rule names another group, not IP addresses,
# so new servers in a group are covered automatically. Port 22 is open nowhere.

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb"
  description = "Load balancer: HTTP and HTTPS from the internet"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name_prefix}-alb" }
}

resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app"
  description = "A servers: Vote and Result"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name_prefix}-app" }
}

resource "aws_security_group" "worker" {
  name        = "${var.name_prefix}-worker"
  description = "B servers: worker"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name_prefix}-worker" }
}

resource "aws_security_group" "data" {
  name        = "${var.name_prefix}-data"
  description = "C servers: Redis and PostgreSQL DB"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name_prefix}-data" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anyone (redirected to HTTPS)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from anyone"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# the load balancer (alb) may send to servers wearing the app badge, on ports 8080 to 8081.
resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To Vote (8080) and Result (8081) only"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 8080 # from-to means range
  to_port                      = 8081
}

# Servers wearing the app badge accept connections from the load balancer (alb) only, on ports 8080 to 8081.
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "Vote and Result, only from the load balancer"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8080 # from-to means range
  to_port                      = 8081
}

locals {
  data_ingress = {
    redis_from_app       = { port = 6379, from = aws_security_group.app.id, why = "Vote puts votes into Redis" }
    redis_from_worker    = { port = 6379, from = aws_security_group.worker.id, why = "Workers take votes from Redis" }
    postgres_from_app    = { port = 5432, from = aws_security_group.app.id, why = "Result reads the totals" }
    postgres_from_worker = { port = 5432, from = aws_security_group.worker.id, why = "Workers save votes" }
    postgres_replication = { port = 5432, from = aws_security_group.data.id, why = "C1 and C2 copy the database" }
  }
}

# For each line of data_ingress table: servers wearing the data badge accept connections
# from the named badge, on that one port.
resource "aws_vpc_security_group_ingress_rule" "data" {
  for_each                     = local.data_ingress
  security_group_id            = aws_security_group.data.id
  description                  = each.value.why
  referenced_security_group_id = each.value.from
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
}

# Servers wearing the app, worker or data badge may connect to or send data anywhere, on any port.
resource "aws_vpc_security_group_egress_rule" "servers_out" {
  for_each = {
    app    = aws_security_group.app.id
    worker = aws_security_group.worker.id
    data   = aws_security_group.data.id
  }
  security_group_id = each.value
  description       = "All outgoing traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # every protocol and port
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-default-unused" }

}