variable "cluster_name" {
  description = "Name of EKS Cluster"
  type        = string
}

variable "addon_name" {
  description = "Name of Addon"
  type        = string
}

variable "configuration_values" {
  description = "JSON encoded config values"
  type        = string
  default     = ""
}
