###########################
# Load availability zones #
###########################
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "seoul" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

############################
# Remote State from shared #
############################
data "terraform_remote_state" "shared" {
  backend = "s3"
  config = {
    bucket = "hivewiki-infra-state-bucket"
    key    = "shared/terraform.tfstate"
    region = var.aws_region
  }
}

##########
# locals #
##########
locals {
  vpc_cidr = "10.0.0.0/16"
  az_a     = data.aws_availability_zones.seoul.names[0]
  az_c     = data.aws_availability_zones.seoul.names[2]

  # Enable/disable EKS private access
  eks_private_mode = true

  # EKS Addon list
  eks_addons = toset([
    "coredns",
    "kube-proxy",
    "vpc-cni",
    "aws-ebs-csi-driver",
    "eks-pod-identity-agent",
  ])

  # Pod identity associations
  karpenter_policies = concat(
    [
      {
        name = "node-lifecycle"
        arn  = module.karpenter_prerequisite.controller_policy_arns.node_lifecycle
      },
      {
        name = "iam-integration"
        arn  = module.karpenter_prerequisite.controller_policy_arns.iam_integration
      },
      {
        name = "eks-integration"
        arn  = module.karpenter_prerequisite.controller_policy_arns.eks_integration
      },
      {
        name = "resource-discovery"
        arn  = module.karpenter_prerequisite.controller_policy_arns.resource_discovery
      },
    ],
    var.enable_interruption_handling ? [
      {
        name = "interruption"
        arn  = module.karpenter_prerequisite.controller_policy_arns.interruption
      }
    ] : []
  )
  pod_identity_associations = {
    vpc_cni = {
      role_name = "${var.cluster_name}-vpc-cni"
      policies = [
        {
          name = "amazon-eks-cni-policy"
          arn  = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
        }
      ]
      namespace       = "kube-system"
      service_account = "aws-node"
    }

    ebs_csi = {
      role_name = "${var.cluster_name}-ebs-csi"
      policies = [
        {
          name = "amazon-ebs-csi-driver-policy"
          arn  = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
        }
      ]
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }

    karpenter = {
      role_name       = "${var.cluster_name}-karpenter-controller"
      policies        = local.karpenter_policies
      namespace       = "karpenter"
      service_account = "karpenter"
    }

    argocd_image_updater = {
      role_name = "${var.cluster_name}-argocd-image-updater"
      policies = [
        {
          name = "${var.cluster_name}-argocd-image-updater"
          arn  = aws_iam_policy.argocd_image_updater.arn
        }
      ]
      namespace       = "argocd"
      service_account = "argocd-image-updater"
    }

    loki = {
      role_name = "${var.cluster_name}-loki"
      policies = [
        {
          name = aws_iam_policy.loki.name
          arn  = aws_iam_policy.loki.arn
        }
      ]
      namespace       = "monitoring"
      service_account = "loki"
    }

    yace = {
      role_name = "${var.cluster_name}-yace"
      policies = [
        {
          name = aws_iam_policy.yace.name
          arn  = aws_iam_policy.yace.arn
        }
      ]
      namespace       = "monitoring"
      service_account = "yace"
    }

  }
}

#######
# VPC #
#######
module "vpc" {
  source       = "../../../modules/vpc"
  cluster_name = var.cluster_name
  cidr_block   = local.vpc_cidr
  azs = {
    a = local.az_a
    c = local.az_c
  }
  public_subnets = {
    a = {
      cidr = "10.0.0.0/24"
      az   = "a"
    }
    c = {
      cidr = "10.0.1.0/24"
      az   = "c"
    }
  }
  private_subnets = {
    a = {
      cidr = "10.0.100.0/24"
      az   = "a"
    }
    c = {
      cidr = "10.0.101.0/24"
      az   = "c"
    }
  }
  db_subnets = {
    a = {
      cidr = "10.0.200.0/24"
      az   = "a"
    }
    c = {
      cidr = "10.0.201.0/24"
      az   = "c"
    }
  }

  # When reducing the number of NAT gateway AZs,
  # it is safer to first set `natgw_az` to an empty list and apply,
  # then recreate the NAT gateway with the desired AZs.
  natgw_az = ["a", "c"]
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

  cidr_ipv4   = "10.0.0.0/16"
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
}

module "vpc-endpoints" {
  source = "../../../modules/vpc-endpoint"
  vpc_id = module.vpc.vpc_id
  endpoints = {
    ec2 = {
      service_name        = "com.amazonaws.${var.aws_region}.ec2"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    ecr_api = {
      service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    ecr_dkr = {
      service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    s3 = {
      service_name    = "com.amazonaws.${var.aws_region}.s3"
      endpoint_type   = "Gateway"
      route_table_ids = [module.vpc.private_route_table_id]
    }
    cloudwatch_logs = {
      service_name        = "com.amazonaws.${var.aws_region}.logs"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    sts = {
      service_name        = "com.amazonaws.${var.aws_region}.sts"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    eks_auth = {
      service_name        = "com.amazonaws.${var.aws_region}.eks-auth"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    eks = {
      service_name        = "com.amazonaws.${var.aws_region}.eks"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
    }
    sqs = {
      service_name        = "com.amazonaws.${var.aws_region}.sqs"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnet_ids
      security_group_ids  = [aws_security_group.vpce.id]
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

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]
  log_retention_in_days = var.log_retention_in_days

  cp_scaling_tier = "standard"
}

######################
# EKS - Access Entry #
######################
module "eks_access_entry_private" {
  count  = local.eks_private_mode ? 1 : 0
  source = "../../../modules/eks-access-entry"

  cluster_name      = module.eks_cluster.cluster_name
  principal_arn     = module.bastion[0].bastion_role_arn
  kubernetes_groups = []

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

  cluster_name      = module.eks_cluster.cluster_name
  principal_arn     = data.terraform_remote_state.shared.outputs.eks_admin_sso_principal_arn
  kubernetes_groups = []

  eks_access_policy_association = {
    clusteradmin = {
      policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
      access_scope_type = "cluster"
    }
  }
}

module "eks_access_entry_karpenter_node" {
  source = "../../../modules/eks-access-entry"

  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.karpenter_prerequisite.node_role_arn
  type          = "EC2_LINUX"
}

#####################################
# EKS - Node Group                  #
# Desired Node group size is ignored #
# when comparing the state           #
#####################################
module "eks_node_group" {
  source = "../../../modules/eks-node-group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = "${var.cluster_name}-ng"

  ami_type       = "AL2023_ARM_64_STANDARD"
  subnet_ids     = module.vpc.private_subnet_ids
  instance_types = ["t4g.large"]

  capacity_type = "ON_DEMAND"
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

  taints = {}

  # Role policy Attachment
  # check: https://docs.aws.amazon.com/eks/latest/userguide/create-node-role.html
  role_policy_attachment = [
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
}

################
# EKS - Addons #
################
module "eks_addons" {
  source   = "../../../modules/eks-addons"
  for_each = local.eks_addons

  cluster_name = module.eks_cluster.cluster_name
  addon_name   = each.value
}

###################################
# EKS - Pod identity associations #
###################################
module "pod_identity_association" {
  source   = "../../../modules/eks-pod-identity-association"
  for_each = local.pod_identity_associations

  cluster_name    = module.eks_cluster.cluster_name
  role_name       = each.value.role_name
  policies        = each.value.policies
  namespace       = each.value.namespace
  service_account = each.value.service_account
}

################
# Bastion Host #
################
module "bastion" {
  count  = local.eks_private_mode ? 1 : 0
  source = "../../../modules/ec2-ssm-bastion"

  name                        = "bastion-prod"
  vpc_id                      = module.vpc.vpc_id
  subnet_id                   = module.vpc.private_subnet_ids[0]
  instance_type               = "t4g.nano"
  eks_arn                     = module.eks_cluster.arn
  associate_public_ip_address = false
}

#######
# RDS #
#######
module "rds" {
  source = "../../../modules/rds"

  db_identifier = "hivewiki-prod"

  vpc_id                    = module.vpc.vpc_id
  subnet_ids                = module.vpc.db_subnet_ids
  allowed_security_group_id = module.eks_cluster.cluster_security_group_id

  db_engine         = "postgres"
  db_engine_version = "18.3"
  db_instance_class = "db.t4g.large"
  db_storage_size   = 60
  db_storage_type   = "gp3"

  db_port  = 5432
  multi_az = false

  db_username = "hivewiki"
  db_password = var.db_password
  db_name     = "hivewiki"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  log_retention_in_days           = var.log_retention_in_days

  backup_retention_period = 3
  backup_window           = "22:00-23:00"
  maintenance_window      = "Sun:21:00-Sun:22:00"
  apply_immediately       = true
}

################################
# Elasticache - Serverless     #
# Using default KMS encrpytion #
################################
module "cache" {
  source = "../../../modules/elasticache-serverless"

  cache_name                = "hivewiki-prod"
  vpc_id                    = module.vpc.vpc_id
  subnet_ids                = module.vpc.db_subnet_ids
  allowed_security_group_id = module.eks_cluster.cluster_security_group_id

  max_cache_usage     = 1
  max_ecpu_per_second = 1000
  max_snapshot        = null
}

##########################
# Karpenter Prerequisite #
##########################
module "karpenter_prerequisite" {
  source = "../../../modules/karpenter-prerequisite"

  cluster_name                 = var.cluster_name
  aws_region                   = var.aws_region
  cluster_security_group_id    = module.eks_cluster.cluster_security_group_id
  enable_interruption_handling = var.enable_interruption_handling
}

####################################
# IAM for Load Balancer Controller #
####################################
data "aws_iam_policy_document" "lbc" {
  statement {
    effect = "Allow"

    actions = [
      "iam:CreateServiceLinkedRole",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:GetCoipPoolUsage",
      "ec2:DescribeCoipPools",
      "ec2:GetSecurityGroupsForVpc",
      "ec2:DescribeIpamPools",
      "ec2:DescribeRouteTables",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTrustStores",
      "elasticloadbalancing:DescribeListenerAttributes",
      "elasticloadbalancing:DescribeCapacityReservation",
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "cognito-idp:DescribeUserPoolClient",
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "iam:ListServerCertificates",
      "iam:GetServerCertificate",
      "waf-regional:GetWebACL",
      "waf-regional:GetWebACLForResource",
      "waf-regional:AssociateWebACL",
      "waf-regional:DisassociateWebACL",
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "shield:GetSubscriptionState",
      "shield:DescribeProtection",
      "shield:CreateProtection",
      "shield:DeleteProtection",
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:CreateSecurityGroup",
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:CreateTags",
    ]

    resources = [
      "arn:aws:ec2:*:*:security-group/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateSecurityGroup"]
    }

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]

    resources = [
      "arn:aws:ec2:*:*:security-group/*",
    ]

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["true"]
    }

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DeleteSecurityGroup",
    ]

    resources = ["*"]

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    effect = "Allow"

    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
    ]

    resources = ["*"]

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    effect = "Allow"

    actions = [
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]

    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
    ]

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["true"]
    }

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    effect = "Allow"

    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]

    resources = [
      "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyListenerAttributes",
      "elasticloadbalancing:ModifyCapacityReservation",
      "elasticloadbalancing:ModifyIpPools",
    ]

    resources = ["*"]

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    effect = "Allow"

    actions = [
      "elasticloadbalancing:AddTags",
    ]

    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "elasticloadbalancing:CreateAction"
      values = [
        "CreateTargetGroup",
        "CreateLoadBalancer",
      ]
    }

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    effect = "Allow"

    actions = [
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
    ]

    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "elasticloadbalancing:SetWebAcl",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:SetRulePriorities",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "lbc" {
  name   = "${var.cluster_name}-load-balancer-controller"
  path   = "/"
  policy = data.aws_iam_policy_document.lbc.json
}

data "aws_iam_policy_document" "alb_logging" {
  statement {
    sid    = "AllowALBLogDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }

    actions = ["s3:PutObject"]
    resources = [
      "arn:aws:s3:::${var.cluster_name}-alb-gw-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
    ]
  }
}

####################
# S3 (ALB Logging) #
####################
module "alb_logging" {
  source             = "../../../modules/s3-archive"
  bucket_name        = "${var.cluster_name}-alb-gw-logs"
  bucket_policy_json = data.aws_iam_policy_document.alb_logging.json
  bucket_lifecycle_rules = {
    daily = {
      enabled         = true
      id              = "daily-backup-retention"
      prefix          = ""
      transitions     = []
      expiration_days = var.log_retention_in_days
    }
  }
}

#############################
# IAM Role for external-dns #
#############################
data "aws_iam_policy_document" "external_dns" {
  version = "2012-10-17"

  statement {
    sid = "PermitListHostedZones"
    actions = [
      "route53:ListHostedZones",
    ]
    resources = ["*"]
  }

  statement {
    sid = "PermitRecordSetsOperations"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResources"
    ]
    resources = [
      data.terraform_remote_state.shared.outputs.route53_zone_arn
    ]
  }
}

resource "aws_iam_policy" "external_dns" {
  name        = "${var.cluster_name}-external-dns-policy"
  path        = "/"
  description = "Policy for external-dns in ${var.cluster_name}"
  policy      = data.aws_iam_policy_document.external_dns.json
}

#######
# WAF #
#######
module "waf_logging" {
  source      = "../../../modules/s3-archive"
  bucket_name = "aws-waf-logs-${var.cluster_name}"
  bucket_lifecycle_rules = {
    daily = {
      enabled         = true
      id              = "waf-log-retention"
      prefix          = ""
      transitions     = []
      expiration_days = var.log_retention_in_days
    }
  }
}

module "waf" {
  source = "../../../modules/waf"

  cluster_name           = var.cluster_name
  rate_limit             = 5000
  rate_limit_eval_window = 300
  waf_rule_action        = var.waf_rule_action
  log_destination_configs = [
    module.waf_logging.bucket_arn
  ]
}

########################
# ArgoCD Image Updater #
########################
data "aws_iam_policy_document" "argocd_image_updater" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetAuthorizationToken",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:GetRepositoryPolicy",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "argocd_image_updater" {
  name        = "${var.cluster_name}-argocd-image-updater"
  path        = "/"
  description = "Policy for argocd-image-updater in ${var.cluster_name}"
  policy      = data.aws_iam_policy_document.argocd_image_updater.json
}

##########
## Loki ##
##########

###################
# S3 (Loki Chunk) #
###################
module "loki_chunk_bucket" {
  source      = "../../../modules/s3-archive"
  bucket_name = "${var.cluster_name}-loki-chunk"
  bucket_lifecycle_rules = {
    daily = {
      enabled = true
      id      = "daily-backup-retention"
      prefix  = ""
      transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        }
      ]
      expiration_days = 90
    }
  }
}

###################
# S3 (Loki Ruler) #
###################
module "loki_ruler_bucket" {
  source      = "../../../modules/s3-archive"
  bucket_name = "${var.cluster_name}-loki-ruler"
}

data "aws_iam_policy_document" "loki" {
  statement {
    sid    = "Allow access for loki"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = [
      module.loki_chunk_bucket.bucket_arn,
      "${module.loki_chunk_bucket.bucket_arn}/*",
      module.loki_ruler_bucket.bucket_arn,
      "${module.loki_ruler_bucket.bucket_arn}/*"
    ]
  }
}

resource "aws_iam_policy" "loki" {
  name        = "${var.cluster_name}-loki"
  path        = "/"
  description = "Policy for loki in ${var.cluster_name}"
  policy      = data.aws_iam_policy_document.loki.json
}

########
# YACE #
########
data "aws_iam_policy_document" "yace" {
  statement {
    effect = "Allow"
    actions = [
      "tag:GetResources",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "apigateway:GET",
      "aps:ListWorkspaces",
      "autoscaling:DescribeAutoScalingGroups",
      "dms:DescribeReplicationInstances",
      "dms:DescribeReplicationTasks",
      "ec2:DescribeTransitGatewayAttachments",
      "ec2:DescribeSpotFleetRequests",
      "shield:ListProtections",
      "storagegateway:ListGateways",
      "storagegateway:ListTagsForResource",
      "iam:ListAccountAliases"
    ]
    resources = ["*"]
  }
}
resource "aws_iam_policy" "yace" {
  name        = "${var.cluster_name}-yace"
  path        = "/"
  description = "Policy for yace in ${var.cluster_name}"
  policy      = data.aws_iam_policy_document.yace.json
}

##############
# Log Backup #
##############
module "log_archive_bucket" {
  source = "../../../modules/s3-archive"

  bucket_name = "${var.cluster_name}-log-archive"
  bucket_lifecycle_rules = {
    daily = {
      enabled = true
      id      = "daily-backup-retention"
      prefix  = ""
      transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "DEEP_ARCHIVE"
        }
      ]
    }
  }
}

module "log_archiving" {
  source = "../../../modules/log_archiving"

  firehose_name = "${var.cluster_name}-log-archive"
  bucket_arn    = module.log_archive_bucket.bucket_arn

  log_groups = {
    eks_api = {
      subscription_filter_name = "${var.cluster_name}-eks-api-archive"
      log_group_name           = module.eks_cluster.log_group_name
    }
    rds_postgresql = {
      subscription_filter_name = "${var.cluster_name}-rds-postgresql-archive"
      log_group_name           = module.rds.log_group_name
    }
  }
}
