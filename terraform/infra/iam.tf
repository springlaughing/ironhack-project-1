# The identity every server (A, B, C) gets. No password: AWS gives each server
# temporary keys for this role and replaces them about every hour.
resource "aws_iam_role" "server" {
  name        = "${var.name_prefix}-server"
  description = "Identity of the A, B and C servers: Session Manager and CloudWatch"

  # Trust policy: who may wear this role. Only the EC2 service, for our servers.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.name_prefix}-server" }
}

# Permission 1: servers wearing the role may register with Session Manager,
# so I and Ansible can connect without SSH.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Permission 2: servers wearing the role may send logs and metrics to CloudWatch.
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.server.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# The wrapper that lets EC2 servers wear the role. In #15, each server gets
# iam_instance_profile = aws_iam_instance_profile.server.name
resource "aws_iam_instance_profile" "server" {
  name = "${var.name_prefix}-server"
  role = aws_iam_role.server.name
  tags = { Name = "${var.name_prefix}-server" }
}