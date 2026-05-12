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

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "hivewiki-infra-state-bucket"
    key    = "dev/vpc/terraform.tfstate"
    region = var.aws_region
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
  eks_addons = {
    coredns = {
      name                 = "coredns"
      configuration_values = ""
    },
    kube_proxy = {
      name                 = "kube-proxy"
      configuration_values = ""
    },
    vpc_cni = {
      name = "vpc-cni"
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    },
    aws_ebs_csi_driver = {
      name                 = "aws-ebs-csi-driver"
      configuration_values = ""
    },
    eks_pod_identity_agent = {
      name                 = "eks-pod-identity-agent"
      configuration_values = ""
    }
  }

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
    load_balancer_controller = {
      role_name = "${var.cluster_name}-load-balancer-controller"
      policies = [{
        name = "${var.cluster_name}-load-balancer-controller"
        arn  = aws_iam_policy.lbc.arn
      }]
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
    external_dns = {
      role_name = "${var.cluster_name}-external-dns"
      policies = [
        {
          name = "${var.cluster_name}-external-dns"
          arn  = aws_iam_policy.external_dns.arn
        }
      ]
      namespace       = "external-dns"
      service_account = "external-dns"
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
  vpc_id             = data.terraform_remote_state.vpc.outputs.vpc_id
  vpc_cidr           = local.vpc_cidr
  subnet_ids         = data.terraform_remote_state.vpc.outputs.private_subnet_ids
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
  principal_arn = data.terraform_remote_state.shared.outputs.eks_admin_sso_principal_arn

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
  subnet_ids     = data.terraform_remote_state.vpc.outputs.private_subnet_ids
  instance_types = ["t4g.medium"]

  capacity_type = "ON_DEMAND"
  disk_size     = 20

  # We intentionally use least node group scale, because we use karpenter + spot to reduce costs
  scaling = {
    desired_size = var.eks_node_group_desired_size
    min_size     = var.eks_node_group_min_size
    max_size     = var.eks_node_group_max_size
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

  cluster_name         = module.eks_cluster.cluster_name
  addon_name           = each.value.name
  configuration_values = each.value.configuration_values
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

  name                        = "bastion-dev"
  vpc_id                      = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_id                   = data.terraform_remote_state.vpc.outputs.public_subnet_ids[0]
  instance_type               = "t4g.nano"
  eks_arn                     = module.eks_cluster.arn
  associate_public_ip_address = true
}

################################
# RDS                          #
# Using default KMS encrpytion #
################################
module "rds" {
  source = "../../../modules/rds"

  db_identifier = "hivewiki-dev"

  vpc_id                    = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids                = data.terraform_remote_state.vpc.outputs.db_subnet_ids
  allowed_security_group_id = module.eks_cluster.cluster_security_group_id

  db_engine         = "postgres"
  db_engine_version = "18.3"
  db_instance_class = "db.t4g.micro"
  db_storage_size   = 50
  db_storage_type   = "gp3"

  db_port  = 5432
  multi_az = false

  db_username = "hivewiki"
  db_password = var.db_password
  db_name     = "hivewiki"

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

  cache_name                = "hivewiki-dev"
  vpc_id                    = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids                = data.terraform_remote_state.vpc.outputs.db_subnet_ids
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
module "waf" {
  source = "../../../modules/waf"

  cluster_name           = var.cluster_name
  rate_limit             = 500
  rate_limit_eval_window = 300
  waf_rule_action        = var.waf_rule_action
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
