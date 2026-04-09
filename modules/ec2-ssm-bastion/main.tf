data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_security_group" "bastion" {
  name        = "bastion_ssm"
  description = "Deny inbound traffic and allow outbound traffic"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "bastion_internet" {
  security_group_id = aws_security_group.bastion.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  ip_protocol = "tcp"
  to_port     = 443
}

resource "aws_iam_instance_profile" "ssm" {
  name = "${var.name}-profile"
  role = aws_iam_role.bastion.id
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = var.associate_public_ip_address

  iam_instance_profile = aws_iam_instance_profile.ssm.name

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  user_data                   = file("${path.module}/user_data.sh")
  user_data_replace_on_change = true

  tags = {
    Name = var.name
  }
}

resource "aws_iam_role" "bastion" {
  name = var.name
  path = "/"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEC2SSM"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Purpose = "Bastion"
  }
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "bastion_access_eks" {
  statement {
    sid = "AllowEKStoBastion"
    actions = [
      "eks:DescribeCluster"
    ]
    resources = [
      var.eks_arn
    ]
  }
}

resource "aws_iam_policy" "bastion_access_eks" {
  name   = "${var.name}-access-eks"
  path   = "/"
  policy = data.aws_iam_policy_document.bastion_access_eks.json
}

resource "aws_iam_role_policy_attachment" "bastion_access_eks" {
  role       = aws_iam_role.bastion.name
  policy_arn = aws_iam_policy.bastion_access_eks.arn
}
