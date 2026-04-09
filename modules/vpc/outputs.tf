output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.vpc.id
}

output "public_subnet_ids" {
  value = values(aws_subnet.public)[*].id
}

output "private_subnet_ids" {
  value = values(aws_subnet.private)[*].id
}

output "db_subnet_ids" {
  value = values(aws_subnet.db)[*].id
}

output "private_route_table_id" {
  value = aws_route_table.private_rtb.id
}
