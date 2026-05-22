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

dependency "vpc" {
  config_path = "../../../vpc"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    vpc_id        = "vpc-00000000"
    db_subnet_ids = ["subnet-00000000", "subnet-11111111"]
  }
}

dependency "infra" {
  config_path = "../../../infra"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    cluster_security_group_id = "sg-00000000"
  }
}

inputs = {
  cluster_name              = include.cluster.locals.cluster_name
  resource_prefix           = include.tenant.locals.resource_prefix
  vpc_id                    = dependency.vpc.outputs.vpc_id
  subnet_ids                = dependency.vpc.outputs.db_subnet_ids
  allowed_security_group_id = dependency.infra.outputs.cluster_security_group_id
}
