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

// VPC Endpoints
resource "aws_security_group" "vpce" {
  vpc_id      = module.vpc.vpc_id
  name        = "allow-private-subnets"
  description = "Allow traffic from private subnets"
}

resource "aws_vpc_security_group_ingress_rule" "allow_vpc" {
  security_group_id = aws_security_group.vpce.id

  cidr_ipv4   = "10.1.0.0/16"
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
}

module "vpc-endpoints" {
  source = "../../modules/vpc-endpoint"
  vpc_id = module.vpc.vpc_id
  endpoints = {
    ec2 = {
      service_name        = "com.amazonaws.ap-northeast-2.ec2"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc-pri.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    ecr_api = {
      service_name        = "com.amazonaws.ap-northeast-2.ecr.api"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc-pri.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    ecr_dkr = {
      service_name        = "com.amazonaws.ap-northeast-2.ecr.dkr"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc-pri.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    s3 = {
      service_name    = "com.amazonaws.ap-northeast-2.s3"
      endpoint_type   = "Gateway"
      route_table_ids = [module.vpc-pri.private_route_table_id]
    }
    cloudwatch_logs = {
      service_name        = "com.amazonaws.ap-northeast-2.logs"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc-pri.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    sts = {
      service_name        = "com.amazonaws.ap-northeast-2.sts"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc-pri.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    eks_auth = {
      service_name        = "com.amazonaws.ap-northeast-2.eks-auth"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc-pri.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    eks = {
      service_name        = "com.amazonaws.ap-northeast-2.eks"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc-pri.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
  }
}
