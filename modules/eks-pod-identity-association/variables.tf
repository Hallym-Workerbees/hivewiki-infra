variable "cluster_name" {
  description = "Name of EKS Cluster"
  type        = string
}

variable "role_name" {
  description = "IAM role name to assign pod"
  type        = string
}

variable "policies" {
  description = "IAM Policies"
  type = list(object({
    name = string
    arn  = string
  }))
  default = []
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "service_account" {
  description = "Name of serviceAccount"
  type        = string
}
