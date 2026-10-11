# The private network for the whole app, spanning zones a and b.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # servers can look up names through AWS's built-in DNS
  enable_dns_hostnames = true # needed for private names like db-write.internal

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}