include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "cluster" {
  path   = find_in_parent_folders("cluster.hcl")
  expose = true
}

inputs = {
  cluster_name     = include.cluster.locals.cluster_name
  aws_region       = include.cluster.locals.aws_region
  vpc_cidr         = include.cluster.locals.vpc_cidr
  natgw_azs        = include.cluster.locals.natgw_azs
  enable_full_vpce = include.cluster.locals.enable_full_vpce
}
