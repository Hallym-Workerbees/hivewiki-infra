output "firehose_arn" {
  description = "ARN of the shared Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.default.arn
}

output "firehose_name" {
  description = "Name of the shared Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.default.name
}

output "logs_to_firehose_role_arn" {
  description = "IAM role assumed by CloudWatch Logs to write into Firehose"
  value       = aws_iam_role.logs_to_firehose.arn
}

output "subscription_filters" {
  description = "Created CloudWatch Logs subscription filters"
  value = {
    for key, filter in aws_cloudwatch_log_subscription_filter.default :
    key => {
      name           = filter.name
      log_group_name = filter.log_group_name
    }
  }
}
