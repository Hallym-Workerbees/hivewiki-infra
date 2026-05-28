include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "cluster" {
  path   = find_in_parent_folders("cluster.hcl")
  expose = true
}

terraform {
  source = "../../../modules//stacks/cluster-logging"
}

locals {
  enable_prod_rds_logging = get_env("TG_ENABLE_PROD_RDS_LOGGING", "false") == "true"
}

dependency "infra" {
  config_path = "../infra"

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "output", "state", "destroy", "force-unlock"]
  mock_outputs = {
    eks_log_group_name = "/aws/eks/mock/cluster"
  }
}

dependency "observability" {
  config_path = "../observability"

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "output", "state", "destroy", "force-unlock"]
  mock_outputs = {
    log_archive_bucket_arn = "arn:aws:s3:::mock-log-archive"
  }
}

dependency "dev_rds" {
  config_path = "../tenants/dev/rds"

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "output", "state", "destroy", "force-unlock"]
  mock_outputs = {
    log_group_name = "/aws/rds/instance/hivewiki-dev/postgresql"
  }
}

dependency "prod_rds" {
  config_path = "../tenants/prod/rds"
  enabled     = local.enable_prod_rds_logging

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "output", "state", "destroy", "force-unlock"]
  mock_outputs = {
    log_group_name = "/aws/rds/instance/hivewiki-prod/postgresql"
  }
}

inputs = {
  cluster_name            = include.cluster.locals.cluster_name
  log_archive_bucket_arn  = dependency.observability.outputs.log_archive_bucket_arn
  eks_log_group_name      = dependency.infra.outputs.eks_log_group_name
  dev_rds_log_group_name  = try(dependency.dev_rds.outputs.log_group_name, "/aws/rds/instance/hivewiki-dev/postgresql")
  prod_rds_log_group_name = local.enable_prod_rds_logging ? try(dependency.prod_rds.outputs.log_group_name, "") : ""
}
