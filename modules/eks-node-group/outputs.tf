output "ng_name" {
  value = aws_eks_node_group.ng.node_group_name
}

output "ng_arn" {
  value = aws_eks_node_group.ng.arn
}
