resource "aws_security_group" "eks_control_plane_access" {
  count = var.private_mode ? 1 : 0

  name        = "${var.cluster_name}-eks-control-plane-access"
  description = "Allow bastion to reach EKS private API"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "eks_api_from_vpc" {
  count = var.private_mode ? 1 : 0

  security_group_id = aws_security_group.eks_control_plane_access[0].id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
resource "aws_eks_cluster" "eks" {
  name = var.cluster_name

  access_config {
    authentication_mode = "API"
  }

  role_arn                      = aws_iam_role.eks.arn
  version                       = var.kubernetes_version
  bootstrap_self_managed_addons = var.bootstrap_self_managed_addons
  enabled_cluster_log_types     = var.enabled_cluster_log_types

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = !var.private_mode
    endpoint_private_access = var.private_mode

    security_group_ids = aws_security_group.eks_control_plane_access[*].id
  }

  # Disable Auto-Mode
  compute_config {
    enabled = false
  }

  control_plane_scaling_config {
    tier = var.cp_scaling_tier
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy]

}

# IAM Role for Contorl Plane
resource "aws_iam_role" "eks" {
  name = "${var.cluster_name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks.name
}

resource "aws_cloudwatch_log_group" "eks_control_plane" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_in_days
}
