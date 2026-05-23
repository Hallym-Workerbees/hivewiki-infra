include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "cluster" {
  path   = find_in_parent_folders("cluster.hcl")
  expose = true
}

terraform {
  source = "../../../modules//stacks/cluster-edge"
}

inputs = {
  cluster_name          = include.cluster.locals.cluster_name
  log_retention_in_days = 7
  waf_rule_action       = "count"
  waf_rate_limit        = 500
}
