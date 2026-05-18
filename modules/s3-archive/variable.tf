variable "bucket_name" {
  description = "Backup Bucket name"
  type        = string
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

variable "bucket_policy_json" {
  description = "Optional bucket policy JSON to attach to the bucket"
  type        = string
  default     = null
}
