locals {
  app_pod_identity_associations = {
    web = {
      role_name       = "${var.resource_prefix}-web"
      policies        = [{ name = aws_iam_policy.web.name, arn = aws_iam_policy.web.arn }]
      namespace       = var.web_ns
      service_account = var.web_sa
    }
  }
}

###################
# S3 + CloudFront #
###################
module "web_cloudfront_s3_bucket" {
  source = "../../s3-cloudfront"

  allowed_origins      = var.web_s3_allowed_origins
  bucket_name          = var.static_bucket_name
  enable_custom_domain = true
  zone_id              = var.route53_zone_id
  custom_domains       = var.cloudfront_custom_domains
  acm_certificate_arn  = var.cloudfront_acm_certificate_arn
  bucket_lifecycle_rules = {
    daily = {
      enabled         = true
      id              = "tmp-img-daily-backup-retention"
      prefix          = var.web_tmp_image_bucket_prefix
      transitions     = []
      expiration_days = var.tmp_image_expiration_days
    }
  }
}

module "app_pod_identity_association" {
  source   = "../../eks-pod-identity-association"
  for_each = local.app_pod_identity_associations

  cluster_name    = var.eks_cluster_name
  role_name       = each.value.role_name
  policies        = each.value.policies
  namespace       = each.value.namespace
  service_account = each.value.service_account
}

####################
# IAM Role for Web #
####################
data "aws_iam_policy_document" "web" {
  statement {
    sid     = "S3UploadDeleteImages"
    effect  = "Allow"
    actions = ["s3:PutObject", "s3:DeleteObject"]
    resources = [
      "${module.web_cloudfront_s3_bucket.bucket_arn}/${var.web_profile_image_bucket_prefix}/*",
      "${module.web_cloudfront_s3_bucket.bucket_arn}/${var.web_post_image_bucket_prefix}/*",
      "${module.web_cloudfront_s3_bucket.bucket_arn}/${var.web_community_image_bucket_prefix}/*",
    ]
  }
  statement {
    sid       = "CloudFrontCreateInvalidation"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [module.web_cloudfront_s3_bucket.cloudfront_distribution_arn]
  }
}

resource "aws_iam_policy" "web" {
  name        = "${var.resource_prefix}-web"
  path        = "/"
  description = "IAM Policy for web to access S3 + Cloudfront"
  policy      = data.aws_iam_policy_document.web.json
}
