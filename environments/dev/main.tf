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
# Locals #
##########
locals {
  eks_addons = toset([
    "coredns",
    "eks-pod-identity-agent",
    "aws-ebs-sci-driver"
  ])
}

#######
# VPC #
#######
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
  source = "../../modules/vpc-endpoint"
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
  source = "../../modules/s3-cloudfront"

  bucket_name = "hivewiki-statics-dev"
}


################
# S3 (Archive) #
################
module "s3_archive" {
  source             = "../../modules/s3-archive"
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
  source = "../../modules/eks-cluster"

  cluster_name       = var.cluster_name
  kubernetes_version = "1.35"
  subnet_ids         = module.vpc.private_subnet_ids

  enabled_cluster_log_types = []
  cp_scaling_tier           = "standard"
  # Disable kube-proxy, VPC-CNI
  bootstrap_self_managed_addons = false
}

######################
# EKS - Access Entry #
######################
module "eks_access_entry" {
  source = "../../modules/eks-access-entry"

  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = data.terraform_remote_state.shared.outputs.eks_fullaccess_role_arn

  eks_access_policy_association = {
    clusteradmin = {
      policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
      access_scope_type = "cluster"
    }
  }
}

###############################################################
# EKS - Node Group                                            #
# This module ignores desired size                            #
###############################################################
module "eks_node_group" {
  source = "../../modules/eks-node-group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = "${var.cluster_name}-ng"

  ami_type       = "AL2023_ARM_64_STANDARD"
  subnet_ids     = module.vpc.private_subnet_ids
  instance_types = ["t4g.large"]
  capacity_type  = "ON_DEMAND"
  disk_size      = 20

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
  # NOTE:
  # - You have to grant tolerations to your pods
  # - taint `cilium` ensures application pods will only be scheduled once Cilium is ready to manage them.
  #   - check: https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/
  taints = {
    infra = {
      key    = "dedicated"
      value  = "infra"
      effect = "NO_SCHEDULE"
    },
    cilium = {
      key    = "node.cilium.io/agent-not-ready"
      value  = "true"
      effect = "NO_EXECUTE"
    }
  }

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
  source   = "../../modules/eks-addons"
  for_each = local.eks_addons

  cluster_name = module.eks_cluster.cluster_name
  addon_name   = each.value
}

############################
# EKS - Pod Identity Agent #
############################

########
# Helm #
########
provider "helm" {
  kubernetes = {
    host                   = module.eks_cluster.endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.ca_certificate)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
      command     = "aws"
    }
  }
}

#################
# Helm - Cilium #
#################
# resource "helm_release" "cilium" {
#   name       = cilium
#   repository = "https://helm.cilium.io/"
#   chart      = "cilium"
#   version    = "1.19.2"
#
#   namespace = "kube-system"
#
#   dynamic "set" {
#
#   }
# }


#TODO
# eks-pod-identity-agent add-on
# pod identity association
# 필요하면 추가 add-on (ebs-csi, observability, lb controller 등)
