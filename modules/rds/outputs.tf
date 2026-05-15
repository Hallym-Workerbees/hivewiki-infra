output "db_endpoint" {
  value = aws_db_instance.db.endpoint
}

output "db_identifier" {
  value = aws_db_instance.db.identifier
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.db.name
}
