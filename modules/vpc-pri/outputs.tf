output "private_subnet_ids" {
  value = values(aws_subnet.private)[*].id
}

output "private_route_table_id" {
  value = aws_route_table.private_rtb.id
}
