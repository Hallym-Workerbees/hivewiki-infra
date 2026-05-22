variable "cluster_name" { type = string }
variable "log_archive_bucket_arn" { type = string }
variable "eks_log_group_name" { type = string }
variable "dev_rds_log_group_name" {
  type    = string
  default = ""
}
variable "prod_rds_log_group_name" {
  type    = string
  default = ""
}
