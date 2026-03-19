locals {
  app_repo_names = [
    "hivewiki-chatbot",
    "hivewiki-builder",
    "hivewiki-collector",
    "hivewiki-web"
  ]

  pull_through_cache_rules = {
    k8s = {
      upstream_registry_url = "registry.k8s.io"
    }
    quay = {
      upstream_registry_url = "quay.io"
    }
    ghcr = {
      upstream_registry_url = "ghcr.io"
    }
    docker-hub = {
      upstream_registry_url = "registry-1.docker.io"
    }
  }
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

# Container Registry (ECR)
# We intentionally use managed encryption instead of KMS
# There is currently no regulatory or compliance to use custom-managed keys.

## Application Repositories
resource "aws_ecr_repository" "app_repositories" {
  for_each             = toset(local.app_repo_names)
  name                 = each.value
  image_tag_mutability = "IMMUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  force_delete = false
}

resource "aws_ecr_lifecycle_policy" "app_repositories" {
  for_each   = aws_ecr_repository.app_repositories
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 prod images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["prod", "main", "stable"]
          countType     = "imageCountMoreThan"
          countNumber   = 30
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 dev and staging images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["dev", "staging", "test"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 3
        description  = "Expire untagged images older than 5 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

## ECR Caches for external registries
resource "aws_ecr_pull_through_cache_rule" "cache" {
  for_each = local.pull_through_cache_rules

  ecr_repository_prefix = each.key
  upstream_registry_url = each.value.upstream_registry_url
}

resource "aws_ecr_repository_creation_template" "cache_template" {
  for_each = local.pull_through_cache_rules

  prefix = each.key

  description          = "Template for cache registries"
  image_tag_mutability = "IMMUTABLE"

  applied_for = [
    "PULL_THROUGH_CACHE",
  ]

  encryption_configuration {
    encryption_type = "AES256"
  }

  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire tagged images older than 14 days"
        selection = {
          tagStatus   = "tagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images older than 5 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
