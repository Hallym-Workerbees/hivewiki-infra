variable "name" {
  description = "Name of the instance"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID"
  type        = string
}

variable "instance_type" {
  description = "EC2 Instance Type"
  type        = string
  default     = "t4g.nano"
}

variable "eks_arn" {
  description = "EKS Arn"
  type        = string
}
