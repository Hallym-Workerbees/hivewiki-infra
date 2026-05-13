locals {
  app_pod_identity_associations = {
    web = {
      role_name = "${var.cluster_name}-web"
      policies = [{
        name = aws_iam_policy.web.name
        arn  = aws_iam_policy.web.arn
      }]
      namespace       = var.web_ns
      service_account = var.web_sa
    }
  }
}

###################
# S3 + Cloudfront #
###################
module "web_cloudfront_s3_bucket" {
  source = "../../../modules/s3-cloudfront"

  bucket_name = "hivewiki-statics-dev"

  enable_custom_domain = true
  zone_id              = data.terraform_remote_state.shared.outputs.route53_zone_id
  custom_domains       = var.cloudfront_custom_domains
  acm_certificate_arn  = data.terraform_remote_state.shared.outputs.cloudfront_acm_certificate_arn
}


module "app_pod_identity_association" {
  source   = "../../../modules/eks-pod-identity-association"
  for_each = local.app_pod_identity_associations

  cluster_name    = module.eks_cluster.cluster_name
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
    sid    = "S3UploadDeleteImages"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      "${module.web_cloudfront_s3_bucket.bucket_arn}/${var.web_profile_image_bucket_prefix}/*",
      "${module.web_cloudfront_s3_bucket.bucket_arn}/${var.web_post_image_bucket_prefix}/*"
    ]
  }
  statement {
    sid    = "CloudFrontCreateInvalidation"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation"
    ]
    resources = [
      module.web_cloudfront_s3_bucket.cloudfront_distribution_arn
    ]
  }
}

resource "aws_iam_policy" "web" {
  name        = "${var.cluster_name}-web"
  path        = "/"
  description = "IAM Policy for web to access S3 + Cloudfront"
  policy      = data.aws_iam_policy_document.web.json
}
