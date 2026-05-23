output "loki_chunk_bucket_arn" { value = module.loki_chunk_bucket.bucket_arn }
output "loki_chunk_bucket_name" { value = module.loki_chunk_bucket.bucket_name }
output "loki_ruler_bucket_arn" { value = module.loki_ruler_bucket.bucket_arn }
output "loki_ruler_bucket_name" { value = module.loki_ruler_bucket.bucket_name }
output "alb_bucket_name" { value = module.alb_logging.bucket_name }
output "log_archive_bucket_arn" { value = module.log_archive_bucket.bucket_arn }
output "web_acl_arn" { value = module.waf.web_acl_arn }
