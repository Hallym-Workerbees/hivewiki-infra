variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs"
  type        = list(string)
}

variable "cache_name" {
  description = "Cache Name"
  type        = string
}

variable "allowed_security_group_id" {
  description = "Allowed security group ID"
  type        = string
}

variable "max_cache_usage" {
  description = "Max Cache Usage(GB)"
  type        = number
}

variable "max_ecpu_per_second" {
  description = "Max ecpu per second"
  type        = number
}


variable "max_snapshot" {
  description = "max retention snapshots"
  type        = number
}
