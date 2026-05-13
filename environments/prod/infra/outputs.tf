output "eks_endpoint" {
  value = module.eks_cluster.endpoint
}

output "eks_ca_certificate" {
  value = module.eks_cluster.ca_certificate
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "bastion_id" {
  value = module.bastion[*].bastion_id
}

output "db_endpoint" {
  value = module.rds.db_endpoint
}

output "cache_endponit" {
  value = module.cache.cache_endpoint
}

output "cache_reader_endpoint" {
  value = module.cache.cache_reader_endpoint
}

output "cache_port" {
  value = module.cache.cache_port
}

output "interruption_handling_queue" {
  value = var.enable_interruption_handling ? module.karpenter_prerequisite.sqs_name : ""
}

output "karpenter_node_role_name" {
  value = module.karpenter_prerequisite.node_role_name
}

output "web_acl_arn" {
  value = module.waf.web_acl_arn
}


output "loki_chunk_bucket_name" {
  value = module.loki_chunk_bucket.bucket_name
}

output "loki_ruler_bucket_name" {
  value = module.loki_ruler_bucket.bucket_name
}
