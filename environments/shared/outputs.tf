output "state_bucket_arn" {
  value = aws_s3_bucket.state_backend.arn
}

output "eks_admin_sso_principal_arn" {
  value = local.eks_admin_sso_principal_arn
}
