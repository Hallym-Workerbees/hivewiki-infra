resource "aws_db_subnet_group" "db" {
  name       = var.db_identifier
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "db" {
  name        = "allow-${var.db_identifier}"
  description = "Allow DB Traffic from EKS Security Groups"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "allow_pg" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = var.allowed_security_group_id
  from_port                    = var.db_port
  to_port                      = var.db_port
  ip_protocol                  = "tcp"
}

resource "aws_db_instance" "db" {
  identifier        = var.db_identifier
  engine            = var.db_engine
  engine_version    = var.db_engine_version
  instance_class    = var.db_instance_class
  allocated_storage = var.db_storage_size
  storage_type      = var.db_storage_type

  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]
  multi_az               = var.multi_az
  publicly_accessible    = false
  port                   = var.db_port

  username = var.db_username
  password = var.db_password
  db_name  = var.db_name

  storage_encrypted = true

  backup_retention_period    = var.backup_retention_period
  backup_window              = var.backup_window
  maintenance_window         = var.maintenance_window
  auto_minor_version_upgrade = true
  deletion_protection        = false
  copy_tags_to_snapshot      = true

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  skip_final_snapshot = true
  apply_immediately   = var.apply_immediately
}

resource "aws_cloudwatch_log_group" "db" {
  name = "/aws/rds/instance/${var.db_identifier}/postgresql"

  retention_in_days = var.log_retention_in_days
}
