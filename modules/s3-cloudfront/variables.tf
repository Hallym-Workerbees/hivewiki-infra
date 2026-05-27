variable "bucket_name" {
  description = "name of the bucket"
  type        = string
}

variable "enable_custom_domain" {
  description = "Whether to enable custom domain"
  type        = bool
  default     = false
}

variable "custom_domains" {
  description = "Custom domains for CloudFront"
  type        = list(string)
  default     = null

  validation {
    condition = (
      var.enable_custom_domain == false ||
      var.custom_domains != null
    )

    error_message = "custom_domains must be provided when enable_custom_domain is true."
  }

  validation {
    condition = (
      var.enable_custom_domain == true ||
      var.custom_domains == null
    )

    error_message = "custom_domains can be used only when enable_custom_domain is true."
  }
}

variable "zone_id" {
  description = "Route53 hosted zone id"
  type        = string
  default     = null

  validation {
    condition = (
      var.enable_custom_domain == false ||
      var.zone_id != null
    )

    error_message = "zone_id must be provided when enable_custom_domain is true."
  }

  validation {
    condition = (
      var.enable_custom_domain == true ||
      var.zone_id == null
    )

    error_message = "zone_id can be used only when enable_custom_domain is true."
  }
}

variable "acm_certificate_arn" {
  description = "ACM Certificate ARN"
  type        = string
  default     = null

  validation {
    condition = (
      var.enable_custom_domain == false ||
      var.acm_certificate_arn != null
    )

    error_message = "acm_certificate_arn must be provided when enable_custom_domain is true."
  }

  validation {
    condition = (
      var.enable_custom_domain == true ||
      var.acm_certificate_arn == null
    )

    error_message = "acm_certificate_arn can be used only when enable_custom_domain is true."
  }
}

variable "allowed_origins" {
  description = "List of allowed origins for CORS"
  type        = list(string)
  default     = []
}

variable "bucket_lifecycle_rules" {
  description = "Lifecycle rules for the backup bucket"
  type = map(object({
    enabled = optional(bool, true)
    id      = string
    prefix  = string
    transitions = list(object({
      days          = number
      storage_class = string
    }))
    expiration_days = optional(number)
  }))
  default = {}
}
