variable "cluster_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "db_subnet_ids" {
  type = list(string)
}

variable "eks_admin_sso_principal_arn" {
  type = string
}

variable "route53_zone_arn" {
  type = string
}

# loki S3 버킷 ARN (tenants/*/storage에서 주입)
variable "loki_chunk_bucket_arn" {
  type = string
}

variable "loki_ruler_bucket_arn" {
  type = string
}

variable "eks_private_mode" {
  description = "true = private endpoint + Bastion. false = public endpoint"
  type        = bool
  default     = false
}

variable "enable_interruption_handling" {
  type    = bool
  default = true
}

variable "eks_node_group_desired_size" {
  type    = number
  default = 1
}

variable "eks_node_group_min_size" {
  type    = number
  default = 0
}

variable "eks_node_group_max_size" {
  type    = number
  default = 1
}

variable "log_retention_in_days" {
  type    = number
  default = 7
}
