variable "cluster_name" { type = string }

variable "log_retention_in_days" {
  type    = number
  default = 7
}

variable "waf_rule_action" {
  type    = string
  default = "count"
}
