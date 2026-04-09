############################
# Remote State from shared #
############################
data "terraform_remote_state" "shared" {
  backend = "s3"
  config = {
    bucket = "hivewiki-infra-state-bucket"
    key    = "shared/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

##########
# locals #
##########
locals {
  vpc_cidr = "10.1.0.0/16"

  # Enable/disable EKS private access
  eks_private_mode = false

  # EKS Addon list
  eks_addons = toset([
    "coredns",
    "kube-proxy",
    "vpc-cni",
    "aws-ebs-csi-driver",
    "eks-pod-identity-agent",
  ])
}

#######
# VPC #
#######
module "vpc" {
  source       = "../../../modules/vpc"
  cluster_name = var.cluster_name
  cidr_block   = local.vpc_cidr
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
  natgw_az = ["a"]
}

#################
# VPC Endpoints #
#################
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

module "vpc_endpoints" {
  source = "../../../modules/vpc-endpoint"
  vpc_id = module.vpc.vpc_id
  endpoints = {
    ec2 = {
      service_name        = "com.amazonaws.ap-northeast-2.ec2"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    ecr_api = {
      service_name        = "com.amazonaws.ap-northeast-2.ecr.api"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    ecr_dkr = {
      service_name        = "com.amazonaws.ap-northeast-2.ecr.dkr"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    s3 = {
      service_name    = "com.amazonaws.ap-northeast-2.s3"
      endpoint_type   = "Gateway"
      route_table_ids = [module.vpc.private_route_table_id]
    }
    cloudwatch_logs = {
      service_name        = "com.amazonaws.ap-northeast-2.logs"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    sts = {
      service_name        = "com.amazonaws.ap-northeast-2.sts"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    eks_auth = {
      service_name        = "com.amazonaws.ap-northeast-2.eks-auth"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    eks = {
      service_name        = "com.amazonaws.ap-northeast-2.eks"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
  }
}

###################
# S3 + Cloudfront #
###################
module "s3_statics" {
  source = "../../../modules/s3-cloudfront"

  bucket_name = "hivewiki-statics-dev"
}


################
# S3 (Archive) #
################
module "s3_archive" {
  source             = "../../../modules/s3-archive"
  backup_bucket_name = "hivewiki-archive-bucket-dev"
  backup_bucket_lifecycle_rules = {
    daily = {
      id     = "daily-backup-retention"
      prefix = ""
      transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        { days          = 90
          storage_class = "DEEP_ARCHIVE"
        }
      ]
    }
  }
}

########################################################
# EKS - Cluster                                        #
#                                                      #
# NOTE:                                                #
# By default, EKS secrets are protected with enveloped #
# encryption in EKS version 1.28 or higher             #
########################################################
module "eks_cluster" {
  source = "../../../modules/eks-cluster"

  cluster_name       = var.cluster_name
  kubernetes_version = "1.35"
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = local.vpc_cidr
  subnet_ids         = module.vpc.private_subnet_ids
  private_mode       = local.eks_private_mode

  enabled_cluster_log_types = []
  cp_scaling_tier           = "standard"
  # Disable kube-proxy, VPC-CNI
  bootstrap_self_managed_addons = false
}

######################
# EKS - Access Entry #
######################
module "eks_access_entry_private" {
  count  = local.eks_private_mode ? 1 : 0
  source = "../../../modules/eks-access-entry"

  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.bastion[0].bastion_role_arn

  eks_access_policy_association = {
    clusteradmin = {
      policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
      access_scope_type = "cluster"
    }
  }
}

module "eks_access_entry_public" {
  count  = local.eks_private_mode ? 0 : 1
  source = "../../../modules/eks-access-entry"

  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = data.terraform_remote_state.shared.outputs.eks_fullaccess_role_arn

  eks_access_policy_association = {
    clusteradmin = {
      policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
      access_scope_type = "cluster"
    }
  }
}

######################################
# EKS - Node Group                   #
# Desired Node group size is ignored #
# when comparing the state           #
######################################
module "eks_node_group" {
  source = "../../../modules/eks-node-group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = "${var.cluster_name}-ng"

  ami_type       = "AL2023_ARM_64_STANDARD"
  subnet_ids     = module.vpc.private_subnet_ids
  instance_types = ["t4g.medium"]

  capacity_type = "SPOT"
  disk_size     = 20

  # We intentionally use least node group scale, because we use karpenter + spot to reduce costs
  scaling = {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  # Label for Node
  labels = {
    dedicated = "infra"
  }

  # Pods for operations only(e.g. GitOps, Observability, other system pods)
  taints = {}

  # Role policy Attachment
  # check: https://docs.aws.amazon.com/eks/latest/userguide/create-node-role.html
  role_policy_attachment = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
  ]
}

################
# EKS - Addons #
################
module "eks-addons" {
  source   = "../../../modules/eks-addons"
  for_each = local.eks_addons

  cluster_name = module.eks_cluster.cluster_name
  addon_name   = each.value
}

resource "aws_iam_role" "vpc_cni" {
  name = "${var.cluster_name}-vpc-cni"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_eks_pod_identity_association" "vpc_cni" {
  cluster_name    = module.eks_cluster.cluster_name
  namespace       = "kube-system"
  service_account = "aws-node"
  role_arn        = aws_iam_role.vpc_cni.arn
}

resource "aws_iam_role" "ebs_csi" {
  name = "${var.cluster_name}-ebs-csi"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = module.eks_cluster.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn
}

################
# Bastion Host #
################
module "bastion" {
  count  = local.eks_private_mode ? 1 : 0
  source = "../../../modules/ec2-ssm-bastion"

  name                        = "bastion-dev"
  vpc_id                      = module.vpc.vpc_id
  subnet_id                   = module.vpc.public_subnet_ids[0]
  instance_type               = "t4g.nano"
  eks_arn                     = module.eks_cluster.arn
  associate_public_ip_address = true
}

#######
# RDS #
#######
module "rds" {
  source = "../../../modules/rds"

  db_identifier = "hivewiki-dev"

  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.db_subnet_ids
  eks_security_group_id = module.eks_cluster.cluster_security_group_id

  db_engine         = "postgres"
  db_engine_version = "18.3"
  db_instance_class = "db.t4g.micro"
  db_storage_size   = 50
  db_storage_type   = "gp3"

  db_port  = 5342
  multi_az = false

  db_username = "hivewiki"
  db_password = var.db_password
  db_name     = "hivewiki"

  backup_retention_period = 3
  backup_window           = "22:00-23:00"
  maintenance_window      = "Sun:21:00-Sun:22:00"
  apply_immediately       = true
}
