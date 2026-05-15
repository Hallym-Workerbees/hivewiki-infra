variable "firehose_name" {
  description = "Name of the shared Kinesis Data Firehose delivery stream"
  type        = string
}

variable "bucket_arn" {
  description = "ARN of the S3 bucket that stores archived logs"
  type        = string
}

variable "log_groups" {
  description = "CloudWatch log groups to archive through the shared Firehose stream"
  type = map(object({
    subscription_filter_name = string
    log_group_name           = string
    filter_pattern           = optional(string, "")
  }))
}

variable "s3_prefix" {
  description = "S3 prefix for successful Firehose deliveries"
  type        = string
  default     = "cloudwatch-logs/"
}

variable "s3_error_output_prefix" {
  description = "S3 prefix for failed Firehose deliveries"
  type        = string
  default     = "cloudwatch-logs-errors/!{firehose:error-output-type}/"
}

variable "buffering_size" {
  description = "Size in MiB before Firehose flushes data to S3"
  type        = number
  default     = 5
}

variable "buffering_interval" {
  description = "Buffer interval in seconds before Firehose flushes data to S3"
  type        = number
  default     = 300
}

variable "compression_format" {
  description = "Compression format for data archived by Firehose"
  type        = string
  default     = "GZIP"

  validation {
    condition = contains([
      "UNCOMPRESSED",
      "GZIP",
      "ZIP",
      "Snappy",
      "HADOOP_SNAPPY",
    ], var.compression_format)
    error_message = "compression_format must be one of UNCOMPRESSED, GZIP, ZIP, Snappy, or HADOOP_SNAPPY."
  }
}

variable "firehose_log_retention_in_days" {
  description = "Retention for Firehose delivery logs"
  type        = number
  default     = 14
}
