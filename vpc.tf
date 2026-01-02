data "aws_availability_zones" "available" {}

resource "aws_vpc" "netw" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = format("%s-vpc", local.cluster_name)
    Environment = "dev"
  }
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.netw.id
  cidr_block        = cidrsubnet(aws_vpc.netw.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = merge({
    Name                                        = format("%s-public-%s", local.cluster_name, count.index),
    "kubernetes.io/cluster/${local.cluster_name}" = "owned",
  }, tomap({}))
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.netw.id
  tags   = { Name = format("%s-igw", local.cluster_name) }
}

resource "aws_eip" "nat" {
  vpc = true
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.netw.id
  cidr_block        = cidrsubnet(aws_vpc.netw.cidr_block, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = merge({
    Name                                        = format("%s-private-%s", local.cluster_name, count.index),
    "kubernetes.io/cluster/${local.cluster_name}" = "owned",
  }, tomap({}))
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.netw.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.netw.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
