resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id                  = var.vpc_id
  cidr_block              = each.value.cidr
  availability_zone       = var.azs[each.value.az]
  map_public_ip_on_launch = false

  tags = {
    Name                                        = "${var.cluster_name}-private-subnet-${each.key}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}


# We allocate only 1 EIP for regional NAT, to reduce its fee
resource "aws_eip" "regional_nat" {
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-regional-nat-eip"
  }
}

resource "aws_nat_gateway" "regional_natgw" {
  vpc_id            = var.vpc_id
  availability_mode = "regional"

  availability_zone_address {
    availability_zone = var.azs[var.natgw_az]
    allocation_ids    = [aws_eip.regional_nat.id]
  }

  tags = {
    Name = "${var.cluster_name}-regional-natgw"
  }
}

resource "aws_route_table" "private_rtb" {
  vpc_id = var.vpc_id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.regional_natgw.id
  }
  tags = {
    Name = "${var.cluster_name}-private-rtb"
  }
}


resource "aws_route_table_association" "private_rtb" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_rtb.id
}
