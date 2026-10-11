# The bucket that holds Terraform's state for the voting app.
resource "aws_s3_bucket" "state" {
  bucket = "voting-app-tfstate-evgenia-686699774218" # must be unique in all of AWS

  lifecycle {
    prevent_destroy = true # the state must never be deleted by accident
  }
}

# Keep old versions of the state, so a broken state can be rolled back.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# No DynamoDB table: locking uses a lock file in this bucket (use_lockfile = true).