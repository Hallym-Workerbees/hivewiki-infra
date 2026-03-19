# State Backend (S3)
resource "aws_s3_bucket" "state_backend" {
  bucket = "hivewiki-infra-state-bucket"
}

# We intentionally use S3-managed encryption (SSE-S3 / AES256) instead of SSE-KMS
# - There is currently no regulatory or compliance requirement to use customer-managed KMS keys.
# - SSE-S3 provides encryption at rest with lower operational complexity.
resource "aws_s3_bucket_server_side_encryption_configuration" "state_sse_s3" {
  bucket = aws_s3_bucket.state_backend.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state_public_access_block" {
  bucket                  = aws_s3_bucket.state_backend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state_backend_versioning" {
  bucket = aws_s3_bucket.state_backend.id
  versioning_configuration {
    status = "Enabled"
  }
}
