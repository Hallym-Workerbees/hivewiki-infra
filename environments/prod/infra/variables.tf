variable "cluster_name" {
  type    = string
  default = "hivewiki-prod"
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

variable "cloudfront_custom_domains" {
  description = "value"
  type        = list(string)
  default = [
    "cdn.hive-wiki.com"
  ]
}

variable "web_ns" {
  description = "Kubernetes namespace name for web"
  type        = string
  default     = "hivewiki-web-prod"
}

variable "web_sa" {
  description = "Kubernetes serviceAccount name for web"
  type        = string
  default     = "hivewiki-web-prod"
}
