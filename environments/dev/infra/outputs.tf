output "eks_endpoint" {
  value = module.eks_cluster.endpoint
}

output "eks_ca_certificate" {
  value = module.eks_cluster.ca_certificate
}

output "bastion_id" {
  value = module.bastion[*].bastion_id
}
