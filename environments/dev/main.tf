// vpc
module "vpc" {
  source       = "../../modules/vpc"
  cluster_name = var.cluster_name
  cidr_block   = "10.1.0.0/16"
  azs = {
    a = "ap-northeast-2a"
    c = "ap-northeast-2c"
  }
  public_subnets = {
    a = {
      cidr = "10.1.0.0/24"
      az   = "a"
    }
    c = {
      cidr = "10.1.1.0/24"
      az   = "c"
    }
  }
  db_subnets = {
    a = {
      cidr = "10.1.200.0/24"
      az   = "a"
    }
    c = {
      cidr = "10.1.201.0/24"
      az   = "c"
    }
  }
}

module "vpc-pri" {
  source       = "../../modules/vpc-pri"
  cluster_name = var.cluster_name
  vpc_id       = module.vpc.vpc_id
  azs = {
    a = "ap-northeast-2a"
    c = "ap-northeast-2c"
  }
  private_subnets = {
    a = {
      cidr = "10.1.100.0/24"
      az   = "a"
    }
    c = {
      cidr = "10.1.101.0/24"
      az   = "c"
    }
  }
  natgw_az = "a"
}
