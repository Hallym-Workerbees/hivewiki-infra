variable "cluster_name" { type = string }
variable "resource_prefix" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "allowed_security_group_id" { type = string }
variable "db_instance_class" { type = string }
variable "db_storage_size" { type = number }
variable "enabled_cloudwatch_logs_exports" { type = list(string) }
variable "db_password" {
  type      = string
  sensitive = true
}
variable "log_retention_in_days" { type = number }
variable "multi_az" { type = bool }
