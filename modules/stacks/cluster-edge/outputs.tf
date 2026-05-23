output "alb_bucket_name" {
  value = module.alb_logging.bucket_name
}

output "web_acl_arn" {
  value = module.waf.web_acl_arn
}
