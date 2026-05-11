variable "cluster_name" {
  description = "EKS Cluster Name"
  type        = string
}

variable "rate_limit" {
  description = "Rate limit"
  type        = number
}

variable "rate_limit_eval_window" {
  description = "Rate limit eval window"
  type        = number
}

variable "waf_rule_action" {
  description = "WAF rule action mode. Use `count` for monitoring or `block` for enforcement."
  type        = string
  default     = "count"

  validation {
    condition     = contains(["count", "block"], var.waf_rule_action)
    error_message = "waf_rule_action must be either `count` or `block`."
  }
}
