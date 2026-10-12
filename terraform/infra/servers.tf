# The newest Ubuntu 24.04 image, published by Canonical (the company behind Ubuntu).
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's AWS account
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# Recipe for A servers (Vote, Result): badge "app", the server role, IMDSv2 only.
resource "aws_launch_template" "app" {
  name                   = "${var.name_prefix}-app"
  image_id               = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.app.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.server.name
  }

  # IMDSv2: a server must ask for a token before reading its role's keys.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 1   # the token can't travel past the server itself, so no container can get one

  }
}

# Recipe for B servers (Workers): same, with badge "worker".
resource "aws_launch_template" "worker" {
  name                   = "${var.name_prefix}-worker"
  image_id               = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.worker.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.server.name
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 1   # the token can't travel past the server itself, so no container can get one

  }
}

# A1: Vote and Result, in the app subnet of zone a.
resource "aws_instance" "a1" {
  subnet_id = aws_subnet.app["a"].id
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
  tags = { Name = "${var.name_prefix}-a1", Role = "app" }
}

# B1: the Workers, also in the app subnet of zone a.
resource "aws_instance" "b1" {
  subnet_id = aws_subnet.app["a"].id
  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }
  tags = { Name = "${var.name_prefix}-b1", Role = "worker" }
}

# C1: Redis and PostgreSQL, in the data subnet of zone a. No template: one of a kind.
resource "aws_instance" "c1" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.data["a"].id
  vpc_security_group_ids = [aws_security_group.data.id]
  iam_instance_profile   = aws_iam_instance_profile.server.name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 1   # the token can't travel past the server itself, so no container can get one

  }

  tags = { Name = "${var.name_prefix}-c1", Role = "data" }
}