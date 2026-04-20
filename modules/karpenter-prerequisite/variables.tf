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
