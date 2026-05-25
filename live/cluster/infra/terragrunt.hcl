include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "cluster" {
  path   = find_in_parent_folders("cluster.hcl")
  expose = true
}

terraform {
  source = "../../../modules//stacks/cluster-infra"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    vpc_id             = "vpc-00000000"
    private_subnet_ids = ["subnet-00000000", "subnet-11111111"]
    public_subnet_ids  = ["subnet-22222222", "subnet-33333333"]
    db_subnet_ids      = ["subnet-44444444", "subnet-55555555"]
  }
}

dependency "shared" {
  config_path = "../../shared"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    eks_admin_sso_principal_arn = "arn:aws:iam::000000000000:role/mock"
    route53_zone_arn            = "arn:aws:route53:::hostedzone/MOCK"
    state_bucket_arn            = "arn:aws:s3:::mock-bucket"
  }
}

dependency "observability" {
  config_path = "../observability"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    loki_chunk_bucket_arn = "arn:aws:s3:::mock-loki-chunk"
    loki_ruler_bucket_arn = "arn:aws:s3:::mock-loki-ruler"
  }
}

inputs = {
  cluster_name = include.cluster.locals.cluster_name
  aws_region   = include.cluster.locals.aws_region

  eks_private_mode   = include.cluster.locals.eks_private_mode
  vpc_id             = dependency.vpc.outputs.vpc_id
  vpc_cidr           = include.cluster.locals.vpc_cidr
  private_subnet_ids = dependency.vpc.outputs.private_subnet_ids
  public_subnet_ids  = dependency.vpc.outputs.public_subnet_ids
  db_subnet_ids      = dependency.vpc.outputs.db_subnet_ids

  eks_admin_sso_principal_arn = dependency.shared.outputs.eks_admin_sso_principal_arn
  route53_zone_arn            = dependency.shared.outputs.route53_zone_arn
  loki_chunk_bucket_arn       = dependency.observability.outputs.loki_chunk_bucket_arn
  loki_ruler_bucket_arn       = dependency.observability.outputs.loki_ruler_bucket_arn

  mng_node_disk_size = 30
}
