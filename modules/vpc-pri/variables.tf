variable "cluster_name" {
  description = "Kubernetes cluster name for prefix"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "azs" {
  description = "Availability zone aliases"
  type        = map(string)
}

variable "private_subnets" {
  description = "Private subnets"
  type = map(object({
    cidr = string
    az   = string
  }))
}

variable "natgw_az" {
  description = "EIP alloc az for NATGW"
  type        = string
}
