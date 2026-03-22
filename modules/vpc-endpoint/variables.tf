variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "tags" {
  description = "Global Tags for endpoints"
  type        = map(string)
  default     = {}
}

variable "endpoints" {
  description = "Endpoint Informations"
  type = map(object({
    service_name        = string
    endpoint_type       = string
    private_dns_enabled = optional(bool)
    subnet_ids          = optional(list(string), [])
    security_group_ids  = optional(list(string), [])
    route_table_ids     = optional(list(string), [])
    policy              = optional(string)
    ip_address_type     = optional(string)
    tags                = optional(map(string), {})
  }))
}
