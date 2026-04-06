output "bastion_id" {
  value = aws_instance.bastion.id
}

output "bastion_role_arn" {
  value = aws_iam_role.bastion.arn
}
