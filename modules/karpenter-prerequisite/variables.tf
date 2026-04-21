variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
}

variable "enable_interruption_handling" {
  description = "Whether to enable interruption handling"
  type        = bool
}

variable "cluster_security_group_id" {
  description = "Cluster SG ID"
  type        = string
}
