variable "cluster_name" {
  description = "Kubernetes cluster name for prefix"
  type        = string
}

variable "azs" {
  description = "Availability zone aliases"
  type        = map(string)
}

variable "cidr_block" {
  description = "CIDR block for vpc."
  type        = string
}

variable "public_subnets" {
  description = "Public subnets"
  type = map(object({
    cidr = string
    az   = string
  }))
}

variable "private_subnets" {
  description = "Private subnets"
  type = map(object({
    cidr = string
    az   = string
  }))
}

variable "db_subnets" {
  description = "DB subnets"
  type = map(object({
    cidr = string
    az   = string
  }))
}

variable "natgw_az_keys" {
  description = "NATGW AZ keys (e.g. ['a', 'b'])"
  type        = list(string)
}
