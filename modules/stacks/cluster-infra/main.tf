data "aws_caller_identity" "current" {}

##########
# locals #
##########
locals {
  tolerations = [
    {
      operator = "Exists"
      effect   = "NoSchedule"
    },
    {
      operator = "Exists"
      effect   = "NoExecute"
    }
  ]

  eks_private_mode = var.eks_private_mode

  eks_addons = {
    coredns = {
      name                 = "coredns"
      configuration_values = ""
    }
    kube_proxy = {
      name                 = "kube-proxy"
      configuration_values = ""
    }
    vpc_cni = {
      name = "vpc-cni"
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
        tolerations = local.tolerations
      })
    }
    aws_ebs_csi_driver = {
      name = "aws-ebs-csi-driver"
      configuration_values = jsonencode({
        node = {
          tolerations = local.tolerations
        }
      })
    }
    eks_pod_identity_agent = {
      name = "eks-pod-identity-agent"
      configuration_values = jsonencode({
        tolerations = local.tolerations
      })
    }
  }

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
      role_name       = "${var.cluster_name}-vpc-cni"
      policies        = [{ name = "amazon-eks-cni-policy", arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" }]
      namespace       = "kube-system"
      service_account = "aws-node"
    }
    ebs_csi = {
      role_name       = "${var.cluster_name}-ebs-csi"
      policies        = [{ name = "amazon-ebs-csi-driver-policy", arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy" }]
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
      role_name       = "${var.cluster_name}-load-balancer-controller"
      policies        = [{ name = "${var.cluster_name}-load-balancer-controller", arn = aws_iam_policy.lbc.arn }]
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
    external_dns = {
      role_name       = "${var.cluster_name}-external-dns"
      policies        = [{ name = "${var.cluster_name}-external-dns", arn = aws_iam_policy.external_dns.arn }]
      namespace       = "external-dns"
      service_account = "external-dns"
    }
    argocd_image_updater = {
      role_name       = "${var.cluster_name}-argocd-image-updater"
      policies        = [{ name = "${var.cluster_name}-argocd-image-updater", arn = aws_iam_policy.argocd_image_updater.arn }]
      namespace       = "argocd"
      service_account = "argocd-image-updater"
    }
    loki = {
      role_name       = "${var.cluster_name}-loki"
      policies        = [{ name = aws_iam_policy.loki.name, arn = aws_iam_policy.loki.arn }]
      namespace       = "monitoring"
      service_account = "loki"
    }
    yace = {
      role_name       = "${var.cluster_name}-yace"
      policies        = [{ name = aws_iam_policy.yace.name, arn = aws_iam_policy.yace.arn }]
      namespace       = "monitoring"
      service_account = "yace"
    }
  }
}

########################################################
# EKS - Cluster
########################################################
module "eks_cluster" {
  source = "../../eks-cluster"

  cluster_name       = var.cluster_name
  kubernetes_version = "1.35"
  vpc_id             = var.vpc_id
  vpc_cidr           = var.vpc_cidr
  subnet_ids         = var.private_subnet_ids
  private_mode       = local.eks_private_mode

  enabled_cluster_log_types     = ["api", "audit", "authenticator"]
  log_retention_in_days         = var.log_retention_in_days
  cp_scaling_tier               = "standard"
  bootstrap_self_managed_addons = false
}

######################
# EKS - Access Entry #
######################
module "eks_access_entry_public" {
  count  = local.eks_private_mode ? 0 : 1
  source = "../../eks-access-entry"

  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = var.eks_admin_sso_principal_arn

  eks_access_policy_association = {
    clusteradmin = {
      policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
      access_scope_type = "cluster"
    }
  }
}

module "eks_access_entry_karpenter_node" {
  source = "../../eks-access-entry"

  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.karpenter_prerequisite.node_role_arn
  type          = "EC2_LINUX"
}

######################################
# EKS - Node Group (infra/ops 전용)  #
######################################
module "eks_node_group" {
  source = "../../eks-node-group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = "${var.cluster_name}-ng"

  ami_type       = "AL2023_ARM_64_STANDARD"
  subnet_ids     = var.private_subnet_ids
  instance_types = ["t4g.large"]
  capacity_type  = "ON_DEMAND"
  disk_size      = var.mng_node_disk_size

  scaling = {
    desired_size = var.eks_node_group_desired_size
    min_size     = var.eks_node_group_min_size
    max_size     = var.eks_node_group_max_size
  }

  labels = {
    env      = "shared"
    workload = "system"
  }
  taints = {}

  role_policy_attachment = [
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
}

################
# EKS - Addons #
################
module "eks_addons" {
  source   = "../../eks-addons"
  for_each = local.eks_addons

  cluster_name         = module.eks_cluster.cluster_name
  addon_name           = each.value.name
  configuration_values = each.value.configuration_values
}

###################################
# EKS - Pod Identity Associations #
###################################
module "pod_identity_association" {
  source   = "../../eks-pod-identity-association"
  for_each = local.pod_identity_associations

  cluster_name    = module.eks_cluster.cluster_name
  role_name       = each.value.role_name
  policies        = each.value.policies
  namespace       = each.value.namespace
  service_account = each.value.service_account
}

################
# Bastion Host #
# (eks_private_mode = true 시에만)
################
module "bastion" {
  count  = var.eks_private_mode ? 1 : 0
  source = "../../ec2-ssm-bastion"

  name                        = "${var.cluster_name}-bastion"
  vpc_id                      = var.vpc_id
  subnet_id                   = var.private_subnet_ids[0]
  instance_type               = "t4g.nano"
  eks_arn                     = module.eks_cluster.arn
  associate_public_ip_address = false
}

module "eks_access_entry_bastion" {
  count  = var.eks_private_mode ? 1 : 0
  source = "../../eks-access-entry"

  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.bastion[0].bastion_role_arn

  eks_access_policy_association = {
    clusteradmin = {
      policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
      access_scope_type = "cluster"
    }
  }
}

##########################
# Karpenter Prerequisite #
##########################
module "karpenter_prerequisite" {
  source = "../../karpenter-prerequisite"

  cluster_name                 = var.cluster_name
  aws_region                   = var.aws_region
  cluster_security_group_id    = module.eks_cluster.cluster_security_group_id
  enable_interruption_handling = var.enable_interruption_handling
}
