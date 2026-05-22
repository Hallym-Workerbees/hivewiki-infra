include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "cluster" {
  path   = find_in_parent_folders("cluster.hcl")
  expose = true
}

dependency "infra" {
  config_path = "../infra"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    eks_endpoint              = "https://mock.eks.endpoint"
    eks_ca_certificate        = "bW9jaw=="
    eks_cluster_name          = "hivewiki-dev"
    interruption_handling_queue = "mock-queue"
    karpenter_node_role_name  = "mock-node-role"
  }
}

dependency "edge" {
  config_path = "../edge"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    web_acl_arn = "arn:aws:wafv2:ap-northeast-2:000000000000:regional/webacl/mock/mock"
  }
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    vpc_id = "vpc-00000000"
  }
}

inputs = {
  cluster_name = include.cluster.locals.cluster_name
  aws_region   = include.cluster.locals.aws_region

  eks_endpoint       = dependency.infra.outputs.eks_endpoint
  eks_ca_certificate = dependency.infra.outputs.eks_ca_certificate

  interruption_handling_queue = dependency.infra.outputs.interruption_handling_queue
  karpenter_node_role_name    = dependency.infra.outputs.karpenter_node_role_name

  vpc_id      = dependency.vpc.outputs.vpc_id
  web_acl_arn = dependency.edge.outputs.web_acl_arn
}
