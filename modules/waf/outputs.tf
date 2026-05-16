output "web_acl_arn" {
  value = aws_wafv2_web_acl.alb.arn
}

output "logging_destination_configs" {
  value = try(aws_wafv2_web_acl_logging_configuration.alb[0].log_destination_configs, [])
}
