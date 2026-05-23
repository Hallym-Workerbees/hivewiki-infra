output "eks_endpoint" {
  value = module.eks_cluster.endpoint
}

output "eks_ca_certificate" {
  value = module.eks_cluster.ca_certificate
}

output "eks_cluster_name" {
  value = module.eks_cluster.cluster_name
}

output "eks_cluster_arn" {
  value = module.eks_cluster.arn
}

output "cluster_security_group_id" {
  value = module.eks_cluster.cluster_security_group_id
}

output "eks_log_group_name" {
  value = module.eks_cluster.log_group_name
}

output "karpenter_node_role_name" {
  value = module.karpenter_prerequisite.node_role_name
}

output "interruption_handling_queue" {
  value = var.enable_interruption_handling ? module.karpenter_prerequisite.sqs_name : ""
}

output "bastion_id" {
  value = module.bastion[*].bastion_id
}

output "ng_arn" {
  value = module.eks_node_group.ng_arn
}

output "ng_name" {
  value = module.eks_node_group.ng_name
}
