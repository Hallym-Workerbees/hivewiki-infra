locals {
  ecr_repo_names = [
    "hivewiki-chatbot",
    "hivewiki-builder",
    "hivewiki-collector",
    "hivewiki-web"
  ]
}

// State Backend (S3)
resource "aws_kms_key" "state_key" {
  description             = "This key is used to encrypt tfstate bucket objects"
  deletion_window_in_days = 10
}

resource "aws_s3_bucket" "state_backend" {
  bucket = "hivewiki-infra-state-bucket"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state_kms_encryption" {
  bucket = aws_s3_bucket.state_backend.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.state_key.arn
      sse_algorithm     = "aws:kms"
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

# Container Registory (ECR)
resource "aws_ecr_repository" "repositories" {
  count                = length(local.ecr_repo_names)
  name                 = local.ecr_repo_names[count.index]
  image_tag_mutability = "IMMUTABLE"

  # We intentionally use managed encryption instead of KMS
  # There is currently no regulatory or compliance to use custom-managed keys.
  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  force_delete = false
}
