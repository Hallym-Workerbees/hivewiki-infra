data "aws_caller_identity" "current" {}

data "aws_ssoadmin_instances" "this" {}

locals {
  admins    = ["fudoge"]
  readonlys = ["treeshine", "rilan00"]
  teammates = concat(local.admins, local.readonlys)

  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
  sso_instance_arn  = tolist(data.aws_ssoadmin_instances.this.arns)[0]

  account_id = data.aws_caller_identity.current.account_id

  sso_eks_admin_role_arn_patterns = [
    "arn:aws:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_workerbees-eks-admin_*",
    "arn:aws:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_workerbees-eks-admin_*"
  ]
}

# IAM Users & Groups with Policy
resource "aws_identitystore_user" "workerbees" {
  for_each          = toset(local.teammates)
  identity_store_id = local.identity_store_id

  user_name    = each.value
  display_name = each.value

  name {
    given_name  = each.value
    family_name = "workerbees"
  }
}

resource "aws_identitystore_group" "workerbees_aws_readonly" {
  identity_store_id = local.identity_store_id

  display_name = "workerbees-aws-readonly"
  description  = "Workerbees AWS readonly users"
}

resource "aws_identitystore_group_membership" "workerbees_aws_readonly" {
  for_each          = toset(local.readonlys)
  identity_store_id = local.identity_store_id

  group_id  = aws_identitystore_group.workerbees_aws_readonly.group_id
  member_id = aws_identitystore_user.workerbees[each.value].user_id
}

resource "aws_ssoadmin_permission_set" "workerbees_aws_readonly" {
  name             = "workerbees-aws-readonly"
  description      = "ReadOnlyAccess for workerbees"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT4H"
}

resource "aws_ssoadmin_managed_policy_attachment" "workerbees_aws_readonly" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.workerbees_aws_readonly.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_ssoadmin_account_assignment" "workerbees_aws_readonly" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.workerbees_aws_readonly.arn

  principal_id   = aws_identitystore_group.workerbees_aws_readonly.group_id
  principal_type = "GROUP"

  target_id   = local.account_id
  target_type = "AWS_ACCOUNT"
}

resource "aws_identitystore_group" "workerbees_aws_admin" {
  identity_store_id = local.identity_store_id

  display_name = "workerbees-aws-admin"
  description  = "Workerbees AWS admin users"
}

resource "aws_identitystore_group_membership" "workerbees_aws_admin" {
  for_each          = toset(local.admins)
  identity_store_id = local.identity_store_id

  group_id  = aws_identitystore_group.workerbees_aws_admin.group_id
  member_id = aws_identitystore_user.workerbees[each.value].user_id
}

resource "aws_ssoadmin_permission_set" "workerbees_aws_admin" {
  name             = "workerbees-aws-admin"
  description      = "AdministratorAccess for workerbees"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT4H"
}

resource "aws_ssoadmin_managed_policy_attachment" "workerbees_aws_admin" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.workerbees_aws_admin.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_ssoadmin_account_assignment" "workerbees_aws_admin" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.workerbees_aws_admin.arn

  principal_id   = aws_identitystore_group.workerbees_aws_admin.group_id
  principal_type = "GROUP"

  target_id   = local.account_id
  target_type = "AWS_ACCOUNT"
}

# For EKS Access
resource "aws_identitystore_group" "workerbees_eks_admin" {
  identity_store_id = local.identity_store_id

  display_name = "workerbees-eks-admin"
  description  = "Workerbees EKS admin users"
}

resource "aws_identitystore_group_membership" "workerbees_eks_admin" {
  for_each          = toset(local.teammates)
  identity_store_id = local.identity_store_id

  group_id  = aws_identitystore_group.workerbees_eks_admin.group_id
  member_id = aws_identitystore_user.workerbees[each.value].user_id
}

resource "aws_ssoadmin_permission_set" "workerbees_eks_admin" {
  name             = "workerbees-eks-admin"
  description      = "EKS admin access for workerbees"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT4H"
}

resource "aws_ssoadmin_account_assignment" "eks_admin" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.workerbees_eks_admin.arn

  principal_id   = aws_identitystore_group.workerbees_eks_admin.group_id
  principal_type = "GROUP"

  target_id   = local.account_id
  target_type = "AWS_ACCOUNT"
}

data "aws_iam_roles" "eks_admin_sso_roles" {
  name_regex  = "AWSReservedSSO_workerbees-eks-admin_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"

  depends_on = [aws_ssoadmin_account_assignment.eks_admin]
}

locals {
  eks_admin_sso_principal_arn = one(tolist(data.aws_iam_roles.eks_admin_sso_roles.arns))
}

resource "aws_ssoadmin_permission_set_inline_policy" "workerbees_eks_admin" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.workerbees_eks_admin.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEksDescribeCluster"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      }
    ]
  })
}
