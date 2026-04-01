variable "backup_bucket_name" {
  description = "Backup Bucket name"
  type        = string
}

variable "backup_bucket_lifecycle_rules" {
  description = "Lifecycle rules for the backup bucket"
  type = map(object({
    id     = string
    prefix = string
    transitions = list(object({
      days          = number
      storage_class = string
    }))
    expiration_days = optional(number)
  }))
  default = {}
}
