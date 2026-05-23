data "aws_availability_zones" "seoul" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  az_a = data.aws_availability_zones.seoul.names[0]
  az_c = data.aws_availability_zones.seoul.names[2]

  # Interface VPCE 목록 (enable_full_vpce = true 시 생성)
  interface_endpoints = {
    ec2 = {
      service_name        = "com.amazonaws.${var.aws_region}.ec2"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = try([aws_security_group.vpce[0].id], [])
    }
    ecr_api = {
      service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = try([aws_security_group.vpce[0].id], [])
    }
    ecr_dkr = {
      service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = try([aws_security_group.vpce[0].id], [])
    }
    cloudwatch_logs = {
      service_name        = "com.amazonaws.${var.aws_region}.logs"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = try([aws_security_group.vpce[0].id], [])
    }
    sts = {
      service_name        = "com.amazonaws.${var.aws_region}.sts"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = try([aws_security_group.vpce[0].id], [])
    }
    eks_auth = {
      service_name        = "com.amazonaws.${var.aws_region}.eks-auth"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = try([aws_security_group.vpce[0].id], [])
    }
    eks = {
      service_name        = "com.amazonaws.${var.aws_region}.eks"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = try([aws_security_group.vpce[0].id], [])
    }
    sqs = {
      service_name        = "com.amazonaws.${var.aws_region}.sqs"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = try([aws_security_group.vpce[0].id], [])
    }
  }
}

#######
# VPC #
#######
module "vpc" {
  source       = "../../vpc"
  cluster_name = var.cluster_name
  cidr_block   = var.vpc_cidr
  azs = {
    a = local.az_a
    c = local.az_c
  }
  public_subnets = {
    a = { cidr = "10.1.0.0/24", az = "a" }
    c = { cidr = "10.1.1.0/24", az = "c" }
  }
  private_subnets = {
    a = { cidr = "10.1.100.0/24", az = "a" }
    c = { cidr = "10.1.101.0/24", az = "c" }
  }
  db_subnets = {
    a = { cidr = "10.1.200.0/24", az = "a" }
    c = { cidr = "10.1.201.0/24", az = "c" }
  }
  natgw_az = var.natgw_azs
}

######################################
# Security Group for Interface VPCEs #
# (enable_full_vpce = true 시에만)   #
######################################
resource "aws_security_group" "vpce" {
  count = var.enable_full_vpce ? 1 : 0

  vpc_id      = module.vpc.vpc_id
  name        = "${var.cluster_name}-vpce"
  description = "Allow HTTPS from private subnets to VPC Endpoints"
}

resource "aws_vpc_security_group_ingress_rule" "vpce_allow_vpc" {
  count = var.enable_full_vpce ? 1 : 0

  security_group_id = aws_security_group.vpce[0].id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

#############################
# S3 Gateway VPCE (항상 유지) #
#############################
module "vpce_s3" {
  source = "../../vpc-endpoint"
  vpc_id = module.vpc.vpc_id
  endpoints = {
    s3 = {
      service_name    = "com.amazonaws.${var.aws_region}.s3"
      endpoint_type   = "Gateway"
      route_table_ids = [module.vpc.private_route_table_id]
    }
  }
}

#######################################
# Interface VPCEs (enable_full_vpce)  #
#######################################
module "vpce_interface" {
  count = var.enable_full_vpce ? 1 : 0

  source    = "../../vpc-endpoint"
  vpc_id    = module.vpc.vpc_id
  endpoints = local.interface_endpoints
}
