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

variable "enable_interruption_handling" {
  type    = bool
  default = true
}

variable "terraform_repo_url" {
  type    = string
  default = "https://github.com/Hallym-Workerbees/hivewiki-infra"
}
