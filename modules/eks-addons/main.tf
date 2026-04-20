resource "aws_eks_addon" "addon" {
  cluster_name = var.cluster_name
  addon_name   = var.addon_name

  configuration_values = var.configuration_values
}
