locals {
  app_repo_names = [
    "hivewiki-chatbot",
    "hivewiki-builder",
    "hivewiki-collector",
    "hivewiki-web"
  ]
  cache_creds = {
    docker-hub = {
      username    = var.dockerhub_username
      accessToken = var.dockerhub_access_token
    }
    ghcr = {
      username    = var.ghcr_username
      accessToken = var.ghcr_access_token
    }
  }

  pull_through_cache_rules = {
    k8s = {
      upstream_registry_url = "registry.k8s.io"
      needs_auth            = false
    }
    ecr-public = {
      upstream_registry_url = "public.ecr.aws"
      needs_auth            = false
    }
    quay = {
      upstream_registry_url = "quay.io"
      needs_auth            = false
    }
    ghcr = {
      upstream_registry_url = "ghcr.io"
      needs_auth            = true
    }
    docker-hub = {
      upstream_registry_url = "registry-1.docker.io"
      needs_auth            = true
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
          tagPrefixList = ["prod"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
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
          tagPrefixList = ["dev"]
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
# We use default kms encryption(AWS Managed Keys)
# In addition, credentials are stored in the remote tfstate backend.
# We intentionially chose this strategy to reduce operational complexity
resource "aws_secretsmanager_secret" "cache_cred" {
  for_each    = local.cache_creds
  name        = "ecr-pullthroughcache/${each.key}"
  description = "Credentials for ECP pull through cache: ${each.key}"
}

resource "aws_secretsmanager_secret_version" "cache_cred" {
  for_each  = local.cache_creds
  secret_id = aws_secretsmanager_secret.cache_cred[each.key].id
  secret_string = jsonencode({
    username    = each.value.username
    accessToken = each.value.accessToken
  })
}

resource "aws_ecr_pull_through_cache_rule" "cache" {
  for_each = local.pull_through_cache_rules

  ecr_repository_prefix = each.key
  upstream_registry_url = each.value.upstream_registry_url

  credential_arn = each.value.needs_auth ? aws_secretsmanager_secret.cache_cred[each.key].arn : null
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
          countType   = "sinceImagePulled"
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
