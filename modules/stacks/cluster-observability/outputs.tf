output "loki_chunk_bucket_arn" {
  value = module.loki_chunk_bucket.bucket_arn
}

output "loki_chunk_bucket_name" {
  value = module.loki_chunk_bucket.bucket_name
}

output "loki_ruler_bucket_arn" {
  value = module.loki_ruler_bucket.bucket_arn
}

output "loki_ruler_bucket_name" {
  value = module.loki_ruler_bucket.bucket_name
}

output "log_archive_bucket_arn" {
  value = module.log_archive_bucket.bucket_arn
}
