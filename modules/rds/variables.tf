variable "db_name" {
  description = "Name of db"
  type        = string
}

variable "db_identifier" {
  description = "DB Identifier"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs"
  type        = list(string)
}

variable "eks_security_group_id" {
  description = "EKS security group ID"
  type        = string
}

variable "db_port" {
  description = "Database Port"
  type        = number
}

variable "db_engine" {
  description = "Database Engine"
  type        = string
}

variable "db_engine_version" {
  description = "DB Engine Version"
  type        = string
}

variable "db_instance_class" {
  description = "DB Instance Class"
  type        = string
}

variable "db_storage_size" {
  description = "DB Storage Size"
  type        = number
}

variable "db_storage_type" {
  description = "DB Storage Type"
  type        = string
}

variable "multi_az" {
  description = "Whether to enable mutl az"
  type        = bool
}

variable "db_username" {
  description = "DB Username"
  type        = string
}

variable "db_password" {
  description = "DB Password"
  type        = string
}

variable "backup_retention_period" {
  description = "Backup retention period"
  type        = number
}

variable "backup_window" {
  description = "Preferred backup window"
  type        = string
}

variable "maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
}

variable "apply_immediately" {
  description = "Whether to apply immediately"
  type        = bool
}
