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
    subnet_ids = var.subnet_ids
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
