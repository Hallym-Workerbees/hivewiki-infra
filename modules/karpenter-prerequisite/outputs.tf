output "controller_policy_arns" {
  value = {
    node_lifecycle     = aws_iam_policy.karpenter_controller_node_lifecycle.arn
    iam_integration    = aws_iam_policy.karpenter_controller_iam_integration.arn
    eks_integration    = aws_iam_policy.karpenter_controller_eks_integration.arn
    resource_discovery = aws_iam_policy.karpenter_controller_resource_discovery.arn
    interruption       = var.enable_interruption_handling ? aws_iam_policy.karpenter_controller_interruption[0].arn : null
  }
}

output "sqs_name" {
  value = var.enable_interruption_handling ? aws_sqs_queue.karpenter_interruption[0].name : null
}

output "node_role_arn" {
  value = aws_iam_role.karpenter_node.arn
}

output "node_role_name" {
  value = aws_iam_role.karpenter_node.name
}
