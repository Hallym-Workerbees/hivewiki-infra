locals {
  # cluster.hcl이 있으면 읽고, 없으면 빈 값
  cluster_vars = try(read_terragrunt_config(find_in_parent_folders("cluster.hcl")), { locals = {} })
  tenant_vars  = try(read_terragrunt_config(find_in_parent_folders("tenant.hcl")), { locals = {} })

  aws_region  = try(local.cluster_vars.locals.aws_region, "ap-northeast-2")
  environment = try(local.tenant_vars.locals.env, try(local.cluster_vars.locals.environment, "dev"))
}

remote_state {
  backend = "s3"
  config = {
    bucket       = "hivewiki-infra-state-bucket"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"
  default_tags {
    tags = {
      Environment = "${local.environment}"
      Project     = "Hivewiki"
      ManagedBy   = "OpenTofu"
    }
  }
}
EOF
}
