variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "principal_arn" {
  description = "IAM role ARN registering access policy"
  type        = string
}

variable "kubernetes_groups" {
  description = "List of Kubernetes groups to assign to the principal"
  type        = list(string)
  default     = []
}

variable "type" {
  description = "Access Entry Type"
  type        = string
  default     = "STANDARD"
}

variable "eks_access_policy_association" {
  type = map(object({
    policy_arn        = string
    access_scope_type = string
    namespaces        = optional(list(string))
  }))
  default = {}
  validation {
    condition = alltrue([
      for t in var.eks_access_policy_association :
      contains(["namespace", "cluster"], t.access_scope_type)
    ])
    error_message = "eks_access_policy_association must contain only 'namespace' or 'cluster'"
  }
}
