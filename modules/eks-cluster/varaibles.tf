variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "EKS version"
  type        = string
}

variable "bootstrap_self_managed_addons" {
  description = "Wheter to Enable VPC CNI and kube-proxy"
  type        = bool
  default     = true
}

variable "subnet_ids" {
  description = "Subnet IDs"
  type        = list(string)
}

variable "cp_scaling_tier" {
  description = "Scaling tier for Control Plane"
  type        = string
  default     = "standard"
}

variable "enabled_cluster_log_types" {
  type    = set(string)
  default = []
  validation {
    condition = alltrue([
      for t in var.enabled_cluster_log_types :
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)
    ])
    error_message = "enabled_cluster_log_types must contain only valid EKS control plane log types."
  }
}
