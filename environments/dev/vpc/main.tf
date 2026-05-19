###########################
# Load availability zones #
###########################
data "aws_availability_zones" "seoul" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

##########
# locals #
##########
locals {
  az_a = data.aws_availability_zones.seoul.names[0]
  az_c = data.aws_availability_zones.seoul.names[2]
}

#######
# VPC #
#######
module "vpc" {
  source       = "../../../modules/vpc"
  cluster_name = var.cluster_name
  cidr_block   = "10.1.0.0/16"
  azs = {
    a = local.az_a
    c = local.az_c
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
  # When reducing the number of NAT gateway AZs,
  # it is safer to first set `natgw_az` to an empty list and apply,
  # then recreate the NAT gateway with the desired AZs.
  natgw_az = var.natgw_azs
}

#################
# VPC Endpoints #
#################
module "vpc_endpoints" {
  count = var.enable_vpce ? 1 : 0

  source = "../../../modules/vpc-endpoint"
  vpc_id = module.vpc.vpc_id
  endpoints = {
    s3 = {
      service_name    = "com.amazonaws.${var.aws_region}.s3"
      endpoint_type   = "Gateway"
      route_table_ids = [module.vpc.private_route_table_id]
    }
  }
}
