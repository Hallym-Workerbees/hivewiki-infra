// VPC
resource "aws_vpc" "vpc" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

// Subnets
resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = each.value.cidr
  availability_zone       = var.azs[each.value.az]
  map_public_ip_on_launch = false

  tags = {
    Name                                        = "${var.cluster_name}-public-subnet-${each.key}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = each.value.cidr
  availability_zone       = var.azs[each.value.az]
  map_public_ip_on_launch = false

  tags = {
    Name                                        = "${var.cluster_name}-private-subnet-${each.key}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "db" {
  for_each = var.db_subnets

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = each.value.cidr
  availability_zone       = var.azs[each.value.az]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.cluster_name}-db-subnet-${each.key}"
  }
}

// IGW & NATGW
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_eip" "regional_nat" {
  count  = length(var.natgw_az_keys)
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-regional-nat-eip-${count.index}"
  }
}

resource "aws_nat_gateway" "regional_natgw" {
  vpc_id            = aws_vpc.vpc.id
  availability_mode = "regional"

  dynamic "availability_zone_address" {
    for_each = var.natgw_az_keys

    content {
      availability_zone = var.azs[availability_zone_address.value]
      allocation_ids    = [aws_eip.regional_nat[index(var.natgw_az_keys, availability_zone_address.value)].id]
    }
  }

  tags = {
    Name = "${var.cluster_name}-regional-natgw"
  }
}

// Route Table & Association
resource "aws_route_table" "public_rtb" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${var.cluster_name}-public-rtb"
  }
}

resource "aws_route_table" "private_rtb" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.regional_natgw.id
  }
  tags = {
    Name = "${var.cluster_name}-private-rtb"
  }
}

resource "aws_route_table" "db_rtb" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.cluster_name}-db-rtb"
  }
}

resource "aws_route_table_association" "public_rtb" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_rtb.id
}

resource "aws_route_table_association" "private_rtb" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_rtb.id
}

resource "aws_route_table_association" "db_rtb" {
  for_each       = aws_subnet.db
  subnet_id      = each.value.id
  route_table_id = aws_route_table.db_rtb.id
}
