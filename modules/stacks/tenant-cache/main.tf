module "cache" {
  source = "../../elasticache-serverless"

  cache_name                = var.resource_prefix
  vpc_id                    = var.vpc_id
  subnet_ids                = var.subnet_ids
  allowed_security_group_id = var.allowed_security_group_id

  max_cache_usage     = var.max_cache_usage
  max_ecpu_per_second = var.ecpu_per_second
  max_snapshot        = null
}
