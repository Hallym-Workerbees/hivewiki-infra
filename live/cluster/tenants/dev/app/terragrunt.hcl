include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "cluster" {
  path   = find_in_parent_folders("cluster.hcl")
  expose = true
}

include "tenant" {
  path   = find_in_parent_folders("tenant.hcl")
  expose = true
}

terraform {
  source = "../../../../../modules//stacks/tenant-app"
}

dependency "infra" {
  config_path = "../../../infra"

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "output", "state", "destroy", "force-unlock"]
  mock_outputs = {
    eks_cluster_name = "hivewiki-dev"
  }
}

dependency "shared" {
  config_path = "../../../../shared"

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "output", "state", "destroy", "force-unlock"]
  mock_outputs = {
    route53_zone_id             = "MOCKZONEID"
    cloudfront_acm_certificate_arn = "arn:aws:acm:us-east-1:000000000000:certificate/mock"
  }
}

inputs = {
  cluster_name                    = include.cluster.locals.cluster_name
  resource_prefix                 = include.tenant.locals.resource_prefix
  static_bucket_name              = "hivewiki-statics-dev"
  eks_cluster_name                = dependency.infra.outputs.eks_cluster_name
  route53_zone_id                 = dependency.shared.outputs.route53_zone_id
  cloudfront_acm_certificate_arn  = dependency.shared.outputs.cloudfront_acm_certificate_arn
  web_ns                          = "hivewiki-web-dev"
  web_sa                          = "hivewiki-web-dev"
  cloudfront_custom_domains       = ["attachment.hive-wiki.com"]
  web_s3_allowed_origins = ["https://test.hive-wiki.com", "https://hive-wiki.com"]
  tmp_image_expiration_days = 1
}
