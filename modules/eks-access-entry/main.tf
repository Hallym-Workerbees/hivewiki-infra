resource "aws_eks_access_entry" "access" {
  cluster_name      = var.cluster_name
  principal_arn     = var.principal_arn
  kubernetes_groups = var.type == "STANDARD" ? var.kubernetes_groups : null
  type              = var.type
}

resource "aws_eks_access_policy_association" "access" {
  for_each = var.type == "STANDARD" ? var.eks_access_policy_association : {}

  cluster_name  = var.cluster_name
  principal_arn = var.principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.access_scope_type
    namespaces = each.value.namespaces
  }
}
