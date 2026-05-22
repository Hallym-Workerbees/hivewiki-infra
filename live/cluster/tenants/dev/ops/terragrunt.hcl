include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "cluster" {
  path   = find_in_parent_folders("cluster.hcl")
  expose = true
}

dependency "vpc" {
  config_path = "../../../vpc"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    vpc_id             = "vpc-00000000"
    private_subnet_ids = ["subnet-00000000", "subnet-11111111"]
  }
}

dependency "infra" {
  config_path = "../../../infra"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    eks_cluster_name = "hivewiki-dev"
    ng_arn           = "arn:aws:eks:ap-northeast-2:000000000000:nodegroup/mock/mock/mock"
    ng_name          = "mock-ng"
  }
}

dependency "rds" {
  config_path = "../rds"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    db_identifier = "hivewiki-dev"
  }
}

dependency "cache" {
  config_path = "../cache"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    cache_address = "mock.cache.endpoint"
    cache_port    = 6379
    cache_sg_id   = "sg-00000000"
  }
}

dependency "shared" {
  config_path = "../../../../shared"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    state_bucket_arn = "arn:aws:s3:::mock-bucket"
  }
}

inputs = {
  cluster_name = include.cluster.locals.cluster_name
  aws_region   = include.cluster.locals.aws_region

  eks_cluster_name  = dependency.infra.outputs.eks_cluster_name
  ng_arn            = dependency.infra.outputs.ng_arn
  ng_name           = dependency.infra.outputs.ng_name
  rds_db_identifier = dependency.rds.outputs.db_identifier

  vpc_id             = dependency.vpc.outputs.vpc_id
  private_subnet_ids = dependency.vpc.outputs.private_subnet_ids

  cache_address = dependency.cache.outputs.cache_address
  cache_port    = dependency.cache.outputs.cache_port
  cache_sg_id   = dependency.cache.outputs.cache_sg_id

  state_bucket_arn = dependency.shared.outputs.state_bucket_arn
}
