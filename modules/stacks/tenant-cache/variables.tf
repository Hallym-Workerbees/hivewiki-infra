variable "cluster_name" { type = string }
variable "resource_prefix" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "allowed_security_group_id" { type = string }
variable "max_cache_usage" { type = number }
variable "ecpu_per_second" { type = number }
