locals {
  admins    = ["fudoge"]
  readonlys = ["treeshine", "rilan00"]
  teammates = concat(local.admins, local.readonlys)
}

# IAM Users & Groups with Policy
resource "aws_iam_user" "workerbees" {
  for_each      = toset(local.teammates)
  name          = each.value
  force_destroy = true
}

resource "aws_iam_group" "workerbees_aws_readonly" {
  name = "workerbees-aws-readonly"
}

resource "aws_iam_group_membership" "workerbees_aws_readonly" {
  name  = "workerbees-aws-readonly-group-membership"
  users = local.readonlys
  group = aws_iam_group.workerbees_aws_readonly.name
}

resource "aws_iam_group_policy_attachment" "workerbees_aws_readonly" {
  group      = aws_iam_group.workerbees_aws_readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_group" "workerbees_aws_admin" {
  name = "workerbees-aws-admin"
}

resource "aws_iam_group_membership" "workerbees_aws_admin" {
  name  = "workerbees-aws-admin-group-membership"
  users = local.admins
  group = aws_iam_group.workerbees_aws_admin.name
}

resource "aws_iam_group_policy_attachment" "workerbees_aws_admin" {
  group      = aws_iam_group.workerbees_aws_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# IAM Roles to Access EKS Cluster (STS AssumeRole)
resource "aws_iam_group" "workerbees_eks_admin" {
  name = "workerbees-eks-admin"
}

resource "aws_iam_group_membership" "workerbees_eks_admin" {
  name  = "workerbees-eks-admin-group-membership"
  users = local.teammates
  group = aws_iam_group.workerbees_eks_admin.name
}

data "aws_iam_policy_document" "eks_role_trust" {
  statement {
    sid     = "AllowSpecificIamUserAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [for u in values(aws_iam_user.workerbees) : u.arn]
    }
    # Force MFA
    dynamic "condition" {
      for_each = var.require_mfa ? [1] : []
      content {
        test     = "Bool"
        variable = "aws:MultiFactorAuthPresent"
        values   = ["true"]
      }
    }
  }
}

resource "aws_iam_role" "eks_fullaccess" {
  name                 = "EKSFullAccessRole"
  assume_role_policy   = data.aws_iam_policy_document.eks_role_trust.json
  path                 = "/"
  max_session_duration = 3600

  tags = {
    Purpose = "HumanEKSAccess"
  }
}

data "aws_iam_policy_document" "user_assume_role" {
  statement {
    sid    = "AllowAssumeEksAdminRole"
    effect = "Allow"

    actions = [
      "sts:AssumeRole"
    ]
    resources = [
      aws_iam_role.eks_fullaccess.arn
    ]
  }
}

resource "aws_iam_group_policy" "assume_eks_admin_role" {
  name   = "workerbees-assume-role"
  group  = aws_iam_group.workerbees_eks_admin.name
  policy = data.aws_iam_policy_document.user_assume_role.json
}
