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

variable "log_destination_configs" {
  description = "List of WAF logging destination ARNs. AWS WAF supports a single destination per Web ACL."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.log_destination_configs) <= 1
    error_message = "AWS WAF supports only one logging destination per Web ACL."
  }
}

variable "redacted_single_headers" {
  description = "Request headers to redact from WAF logs"
  type        = list(string)
  default     = ["authorization", "cookie", "x-api-key"]
}
