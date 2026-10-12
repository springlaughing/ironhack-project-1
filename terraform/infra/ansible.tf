# My account number, read at plan time, so the bucket name is unique without typing it.
data "aws_caller_identity" "current" {}

# Ansible's Session Manager connection can't copy files directly: it drops them here,
# and the server downloads them. Only short-lived transfer files, never kept.
resource "aws_s3_bucket" "ansible" {
  bucket        = "${var.name_prefix}-ansible-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # it only ever holds temporary files, so destroy may empty it

  tags = { Name = "${var.name_prefix}-ansible" }
}

resource "aws_s3_bucket_public_access_block" "ansible" {
  bucket                  = aws_s3_bucket.ansible.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ansible" {
  bucket = aws_s3_bucket.ansible.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Clean up leftovers: delete anything older than 1 day.
resource "aws_s3_bucket_lifecycle_configuration" "ansible" {
  bucket = aws_s3_bucket.ansible.id
  rule {
    id     = "delete-transfer-files"
    status = "Enabled"
    filter {}
    expiration {
      days = 1
    }
  }
}

# Free private road from the private subnets to S3, without the NAT.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in aws_route_table.private : rt.id]

  tags = { Name = "${var.name_prefix}-s3" }
}