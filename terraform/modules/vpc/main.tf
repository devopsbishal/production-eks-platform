resource "aws_vpc" "eks-vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = "aws-eks-dev-vpc"
  }
}

resource "aws_internet_gateway" "eks-gw" {
  vpc_id = aws_vpc.eks-vpc.id
  tags = {
    Name = "eks-cluster-dev-gw"
  }
}


resource "aws_subnet" "subnets" {
  vpc_id                  = aws_vpc.eks-vpc.id
  for_each                = { for idx, subnet in var.vpc_subnets : tostring(idx) => subnet }
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = each.value.map_public_ip_on_launch

  tags = {
    Environment = var.environment
  }
}


resource "aws_route_table" "eks-route-table" {
  vpc_id = aws_vpc.eks-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks-gw.id
  }
}

resource "aws_route_table_association" "eks-route-table-assoc" {
  for_each       = { for k, v in aws_subnet.subnets : k => v if v.map_public_ip_on_launch }
  subnet_id      = each.value.id
  route_table_id = aws_route_table.eks-route-table.id
}
