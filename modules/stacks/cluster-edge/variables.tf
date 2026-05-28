variable "cluster_name" { type = string }

variable "log_retention_in_days" {
  type    = number
  default = 7
}

variable "waf_rule_action" {
  type    = string
  default = "count"
}

variable "waf_rate_limit" {
  type    = number
  default = 500
}

variable "enable_force_destroy" {
  type    = bool
  default = false
}
