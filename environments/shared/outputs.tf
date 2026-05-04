output "state_bucket_arn" {
  value = aws_s3_bucket.state_backend.arn
}

output "eks_admin_sso_principal_arn" {
  value = local.eks_admin_sso_principal_arn
}

output "route53_zone_id" {
  value = aws_route53_zone.main.zone_id
}

output "route53_zone_name_servers" {
  value = aws_route53_zone.main.name_servers
}

output "cloudfront_acm_certificate_arn" {
  value = aws_acm_certificate_validation.cloudfront.certificate_arn
}

output "alb_acm_certificate_arn" {
  value = aws_acm_certificate_validation.alb.certificate_arn
}
