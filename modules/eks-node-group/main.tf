resource "aws_eks_node_group" "ng" {
  cluster_name    = var.cluster_name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.ng.arn

  ami_type       = var.ami_type
  instance_types = var.instance_types
  subnet_ids     = var.subnet_ids
  capacity_type  = var.capacity_type
  disk_size      = var.disk_size

  scaling_config {
    desired_size = var.scaling.desired_size
    min_size     = var.scaling.min_size
    max_size     = var.scaling.max_size
  }

  labels = var.labels

  dynamic "taint" {
    for_each = var.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.ng_attachment]
}

resource "aws_iam_role" "ng" {
  name = "${var.node_group_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ng_attachment" {
  for_each = var.role_policy_attachment

  policy_arn = each.value
  role       = aws_iam_role.ng.name
}
