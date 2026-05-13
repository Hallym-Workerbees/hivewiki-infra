variable "cluster_name" {
  description = "EKS cluster name and resource naming prefix"
  type        = string
  default     = "hivewiki-dev"
}

variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "enable_interruption_handling" {
  type    = bool
  default = true
}

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
  default = 15
}

variable "hibernate_db_instance_polling_period_seconds" {
  type    = number
  default = 15
}

variable "reboot_db_instance_polling_period_seconds" {
  type    = number
  default = 15
}

variable "reboot_ng_polling_period_seconds" {
  type    = number
  default = 15
}

variable "reboot_ng_post_scale_up_wait_seconds" {
  type    = number
  default = 30
}

variable "waf_rule_action" {
  description = "WAF rule action mode. `count` monitors only, `block` enforces blocking."
  type        = string
  default     = "count"

  validation {
    condition     = contains(["count", "block"], var.waf_rule_action)
    error_message = "waf_rule_action must be either `count` or `block`."
  }
}

variable "web_profile_image_bucket_prefix" {
  description = "Bucket prefix for profile images"
  type        = string
  default     = "profiles"
}

variable "web_post_image_bucket_prefix" {
  description = "Bucket prefix for post images"
  type        = string
  default     = "post-images"
}
