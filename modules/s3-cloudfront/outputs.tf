output "bucket_arn" {
  value = aws_s3_bucket.statics.arn
}

output "cloudfront_distribution_arn" {
  value = aws_cloudfront_distribution.s3_distribution.arn
}
