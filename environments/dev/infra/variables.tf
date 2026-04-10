variable "cluster_name" {
  description = "EKS cluster name and resource naming prefix"
  type        = string
  default     = "hivewiki-dev"
}

variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "db_password" {
  type      = string
  sensitive = true
}
