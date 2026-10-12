# The private network for the whole app, spanning zones a and b.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # servers can look up names through AWS's built-in DNS
  enable_dns_hostnames = true # needed for private names like db-write.voting.internal

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

# One entry per zone: its AWS zone name and the address range of each subnet.
locals {
  zones = {
    a = { az = "${var.region}a", public = "10.0.0.0/24", app = "10.0.10.0/24", data = "10.0.20.0/24" }
    b = { az = "${var.region}b", public = "10.0.1.0/24", app = "10.0.11.0/24", data = "10.0.21.0/24" }
  }
}

# The door between the network and the internet.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

# Public subnets: the load balancer and the NAT gateway live here.
resource "aws_subnet" "public" {
  for_each          = local.zones
  vpc_id            = aws_vpc.main.id
  availability_zone = each.value.az
  cidr_block        = each.value.public
  tags              = { Name = "${var.name_prefix}-public-${each.key}" }
}

# App subnets: Vote, Result and Worker servers. No public IPs.
resource "aws_subnet" "app" {
  for_each          = local.zones
  vpc_id            = aws_vpc.main.id
  availability_zone = each.value.az
  cidr_block        = each.value.app
  tags              = { Name = "${var.name_prefix}-app-${each.key}" }
}

# Data subnets: Redis and PostgreSQL servers. No public IPs.
resource "aws_subnet" "data" {
  for_each          = local.zones
  vpc_id            = aws_vpc.main.id
  availability_zone = each.value.az
  cidr_block        = each.value.data
  tags              = { Name = "${var.name_prefix}-data-${each.key}" }
}

# Public route table: anything not inside the network goes to the internet gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.name_prefix}-public" }
}

resource "aws_route_table_association" "public" {
  for_each       = local.zones
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

# Private route tables, one per zone. Piece 3 adds the route to the NAT gateway.
resource "aws_route_table" "private" {
  for_each = local.zones
  vpc_id   = aws_vpc.main.id
  tags     = { Name = "${var.name_prefix}-private-${each.key}" }
}

# App and data subnets of a zone share that zone's private route table.
resource "aws_route_table_association" "app" {
  for_each       = local.zones
  subnet_id      = aws_subnet.app[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_route_table_association" "data" {
  for_each       = local.zones
  subnet_id      = aws_subnet.data[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

# A fixed public IP address for each NAT gateway.
resource "aws_eip" "nat" {
  for_each = toset(var.nat_zones)
  domain   = "vpc"
  tags     = { Name = "${var.name_prefix}-nat-${each.key}" }
}

# NAT gateway: lets private servers reach the internet; nothing can reach in.
resource "aws_nat_gateway" "main" {
  for_each      = toset(var.nat_zones)
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id # lives in a public subnet
  tags          = { Name = "${var.name_prefix}-nat-${each.key}" }

  depends_on = [aws_internet_gateway.main] # needs the internet gateway to work
}

# Each private route table sends outside traffic to its own zone's NAT,
# or to the first NAT if its zone has none. No NAT at all: no route.
resource "aws_route" "private_internet" {
  for_each               = { for k, z in local.zones : k => z if length(var.nat_zones) > 0 }
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[contains(var.nat_zones, each.key) ? each.key : var.nat_zones[0]].id
}