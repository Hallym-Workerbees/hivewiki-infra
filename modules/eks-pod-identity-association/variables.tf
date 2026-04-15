variable "cluster_name" {
  description = "Name of EKS Cluster"
  type        = string
}

variable "role_name" {
  description = "IAM role name to assign pod"
  type        = string
}

variable "policy_arn" {
  description = "IAM policy arn"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "service_account" {
  description = "Name of serviceAccount"
  type        = string
}
