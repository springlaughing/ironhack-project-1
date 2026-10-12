# The load balancer: the only part of the system the internet can reach.
# It sits in both public subnets (zones a and b), so it keeps working if one zone fails.
resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  load_balancer_type = "application" # understands HTTP, can route by path
  internal           = false         # internet-facing: gets public addresses
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]

  drop_invalid_header_fields = true # throw away malformed HTTP headers instead of passing them on

  tags = { Name = "${var.name_prefix}-alb" }
}

# Where requests for the voting page go: port 8080 on the A servers.
resource "aws_lb_target_group" "vote" {
  name     = "${var.name_prefix}-vote"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    matcher             = "200" # only "OK" counts as healthy
    interval            = 15    # ask every 15 seconds
    healthy_threshold   = 2     # 2 good answers in a row = healthy
    unhealthy_threshold = 2     # 2 bad answers in a row = unhealthy
  }

  tags = { Name = "${var.name_prefix}-vote" }
}

# Where requests under /result/ go: port 8081 on the A servers.
resource "aws_lb_target_group" "result" {
  name     = "${var.name_prefix}-result"
  port     = 8081
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/result/"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  # Result keeps a live connection (socket.io): keep each browser on the same server.
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400 # 1 day, in seconds
    enabled         = true
  }

  tags = { Name = "${var.name_prefix}-result" }
}

# Put A1 into both groups. A2 (zone b) joins in step 3.
resource "aws_lb_target_group_attachment" "vote_a1" {
  target_group_arn = aws_lb_target_group.vote.arn
  target_id        = aws_instance.a1.id
  port             = 8080
}

resource "aws_lb_target_group_attachment" "result_a1" {
  target_group_arn = aws_lb_target_group.result.arn
  target_id        = aws_instance.a1.id
  port             = 8081
}

# Port 80: no content, only "use HTTPS instead".
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301" # "moved permanently": browsers remember it
    }
  }
}

# Port 443: HTTPS with my certificate. By default everything goes to Vote.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06" # only TLS 1.3 and 1.2
  certificate_arn   = aws_acm_certificate_validation.vote.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vote.arn
  }
}

# Rule 1: "/result" without the slash → send the browser to "/result/".
resource "aws_lb_listener_rule" "result_slash" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  condition {
    path_pattern {
      values = ["/result"]
    }
  }

  action {
    type = "redirect"
    redirect {
      path        = "/result/"
      status_code = "HTTP_301"
    }
  }
}

# Rule 2: everything under "/result/" → Result.
resource "aws_lb_listener_rule" "result" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20

  condition {
    path_pattern {
      values = ["/result/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.result.arn
  }
}