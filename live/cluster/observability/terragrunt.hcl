include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "cluster" {
  path   = find_in_parent_folders("cluster.hcl")
  expose = true
}

inputs = {
  cluster_name = include.cluster.locals.cluster_name
}
