variable "cluster_name" { type = string }
variable "aws_region" { type = string }
variable "eks_cluster_name" { type = string }
variable "ng_arn" { type = string }
variable "ng_name" { type = string }
variable "rds_db_identifier" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "cache_address" { type = string }
variable "cache_port" { type = number }
variable "cache_sg_id" { type = string }
variable "state_bucket_arn" { type = string }

variable "terraform_repo_url" {
  type    = string
  default = "https://github.com/Hallym-Workerbees/hivewiki-infra"
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

variable "hibernate_ng_polling_period_seconds" {
  type    = number
  default = 30
}

variable "hibernate_db_instance_polling_period_seconds" {
  type    = number
  default = 30
}

variable "reboot_db_instance_polling_period_seconds" {
  type    = number
  default = 30
}

variable "reboot_ng_polling_period_seconds" {
  type    = number
  default = 30
}

variable "reboot_ng_post_scale_up_wait_seconds" {
  type    = number
  default = 30
}

variable "hibernate_sched_cron" {
  type    = string
  default = "0 1 ? * TUE-SAT *"
}

variable "reboot_sched_cron" {
  type    = string
  default = "0 17 ? * MON-FRI *"
}
