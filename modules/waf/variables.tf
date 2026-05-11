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
