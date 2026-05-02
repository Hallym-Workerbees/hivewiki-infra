output "cache_endpoint" {
  value = aws_elasticache_serverless_cache.cache.endpoint[0].address
}

output "address" {
  value = aws_elasticache_serverless_cache.cache.endpoint[0].address
}

output "cache_port" {
  value = aws_elasticache_serverless_cache.cache.endpoint[0].port
}

output "cache_reader_endpoint" {
  value = aws_elasticache_serverless_cache.cache.reader_endpoint[0].address
}

output "cache_sg_id" {
  value = aws_security_group.cache.id
}
