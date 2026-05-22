variable "cluster_name" { type = string }
variable "eks_cluster_name" { type = string }
variable "resource_prefix" { type = string }
variable "route53_zone_id" { type = string }
variable "cloudfront_acm_certificate_arn" { type = string }
variable "static_bucket_name" {
  type    = string
  default = "hivewiki-statics-dev"
}

variable "web_ns" {
  type    = string
  default = "hivewiki-web-dev"
}

variable "web_sa" {
  type    = string
  default = "hivewiki-web-dev"
}

variable "web_s3_allowed_origins" {
  type    = list(string)
  default = ["https://test.hive-wiki.com", "https://hive-wiki.com"]
}

variable "cloudfront_custom_domains" {
  type    = list(string)
  default = ["attachment.hive-wiki.com"]
}

variable "web_profile_image_bucket_prefix" {
  type    = string
  default = "profiles"
}

variable "web_post_image_bucket_prefix" {
  type    = string
  default = "post-images"
}
