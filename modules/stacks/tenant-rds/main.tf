module "rds" {
  source = "../../rds"

  db_identifier             = var.resource_prefix
  vpc_id                    = var.vpc_id
  subnet_ids                = var.subnet_ids
  allowed_security_group_id = var.allowed_security_group_id

  db_engine         = "postgres"
  db_engine_version = "18.3"
  db_instance_class = var.db_instance_class
  db_storage_size   = var.db_storage_size
  db_storage_type   = "gp3"
  db_port           = 5432
  multi_az          = var.multi_az

  db_username = "hivewiki"
  db_password = var.db_password
  db_name     = "hivewiki"

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports
  log_retention_in_days           = var.log_retention_in_days

  backup_retention_period = 3
  backup_window           = "22:00-23:00"
  maintenance_window      = "Sun:21:00-Sun:22:00"
  apply_immediately       = true
}
