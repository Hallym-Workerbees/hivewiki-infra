############################
# Optional: allow describing the cluster
# (update-kubeconfig / describe-cluster 등에 필요)
############################

# data "aws_iam_policy_document" "eks_describe_cluster" {
#   statement {
#     sid    = "AllowDescribeSpecificCluster"
#     effect = "Allow"
#
#     actions = [
#       "eks:DescribeCluster"
#     ]
#
#     resources = [
#       data.aws_eks_cluster.this.arn
#     ]
#   }
# }
#
# resource "aws_iam_role_policy" "eks_describe_cluster" {
#   name   = "${var.eks_role_name}-describe-cluster"
#   role   = aws_iam_role.eks_developer_role.id
#   policy = data.aws_iam_policy_document.eks_describe_cluster.json
# }
