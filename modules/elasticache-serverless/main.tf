resource "aws_security_group" "cache" {
  name        = "${var.cache_name}-sg"
  description = "Allow Valkey access from EKS"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "cache_from_eks" {
  security_group_id            = aws_security_group.cache.id
  referenced_security_group_id = var.allowed_security_group_id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_elasticache_serverless_cache" "cache" {
  engine               = "valkey"
  name                 = var.cache_name
  major_engine_version = "8"

  subnet_ids         = var.subnet_ids
  security_group_ids = [aws_security_group.cache.id]

  cache_usage_limits {
    data_storage {
      maximum = var.max_cache_usage
      unit    = "GB"
    }

    ecpu_per_second {
      maximum = var.max_ecpu_per_second
    }
  }

  snapshot_retention_limit = var.max_snapshot
}
