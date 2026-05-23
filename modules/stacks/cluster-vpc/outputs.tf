output "vpc_id" { value = module.vpc.vpc_id }
output "vpc_arn" { value = module.vpc.vpc_arn }
output "public_subnet_ids" { value = module.vpc.public_subnet_ids }
output "private_subnet_ids" { value = module.vpc.private_subnet_ids }
output "db_subnet_ids" { value = module.vpc.db_subnet_ids }
output "private_route_table_id" { value = module.vpc.private_route_table_id }
