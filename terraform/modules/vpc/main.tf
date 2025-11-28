# Generate subnets dynamically from VPC CIDR
locals {
  # Add public and private subnet counts to get total subnets
  total_subnets = var.subnet_config.number_of_public_subnets + var.subnet_config.number_of_private_subnets

  new_bits = ceil(log(local.total_subnets, 2))

  vpc_subnets = [
    for idx in range(local.total_subnets) : {
      cidr_block              = cidrsubnet(var.vpc_cidr_block, local.new_bits, idx)
      availability_zone       = var.availability_zones[idx % length(var.availability_zones)]
      map_public_ip_on_launch = idx < var.subnet_config.number_of_public_subnets
    }
  ]

  public_subnets = {
    for idx, subnet in local.vpc_subnets : tostring(idx) => subnet
    if subnet.map_public_ip_on_launch
  }

  # HA: all public subnets | Single: just the first one
  nat_gateway_subnets = var.enable_ha_nat_gateways ? local.public_subnets : {
    "0" = local.public_subnets["0"]
  }
}

resource "aws_vpc" "eks_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.environment}-eks-vpc"
      Environment = var.environment
  })
}

resource "aws_internet_gateway" "eks_gw" {
  vpc_id = aws_vpc.eks_vpc.id
  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.environment}-eks-gw"
      Environment = var.environment
  })
}


resource "aws_subnet" "eks_subnets" {
  vpc_id                  = aws_vpc.eks_vpc.id
  for_each                = { for idx, subnet in local.vpc_subnets : tostring(idx) => subnet }
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = each.value.map_public_ip_on_launch

  tags = merge(
    var.resource_tag,
    {
      Name                                                   = "${var.environment}-${each.value.map_public_ip_on_launch ? "public" : "private"}-subnet-${each.value.availability_zone}"
      Environment                                            = var.environment
      "kubernetes.io/role/elb"                               = each.value.map_public_ip_on_launch ? "1" : ""
      "kubernetes.io/role/internal-elb"                      = each.value.map_public_ip_on_launch ? "" : "1"
      "kubernetes.io/cluster/${var.environment}-eks-cluster" = "shared"
  })
}

resource "aws_eip" "eks_eip" {
  for_each = local.nat_gateway_subnets
  domain   = "vpc"

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.environment}-lb-eip-${each.value.availability_zone}"
      Environment = var.environment
  })
}


resource "aws_nat_gateway" "eks_nat_gateway" {
  for_each      = local.nat_gateway_subnets
  allocation_id = aws_eip.eks_eip[each.key].id
  subnet_id     = aws_subnet.eks_subnets[each.key].id

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.environment}-nat-gateway-${each.value.availability_zone}"
      Environment = var.environment
  })

  depends_on = [aws_internet_gateway.eks_gw]
}

resource "aws_route_table" "eks_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = var.internet_cidr_block
    gateway_id = aws_internet_gateway.eks_gw.id
  }

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.environment}-eks-route-table"
      Environment = var.environment
  })
}

resource "aws_route_table_association" "eks_route_table_assoc" {
  for_each       = { for k, v in aws_subnet.eks_subnets : k => v if v.map_public_ip_on_launch }
  subnet_id      = each.value.id
  route_table_id = aws_route_table.eks_route_table.id
}

resource "aws_route_table" "eks_private_route_table" {
  vpc_id   = aws_vpc.eks_vpc.id
  for_each = { for idx, subnet in local.vpc_subnets : tostring(idx) => subnet if !subnet.map_public_ip_on_launch }

  route {
    cidr_block = var.internet_cidr_block
    nat_gateway_id = var.enable_ha_nat_gateways ? [
      for k, nat in aws_nat_gateway.eks_nat_gateway : nat.id
      if aws_subnet.eks_subnets[k].availability_zone == each.value.availability_zone
    ][0] : aws_nat_gateway.eks_nat_gateway["0"].id
  }

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.environment}-eks-private-route-table"
      Environment = var.environment
  })
}

resource "aws_route_table_association" "eks_private_route_table_assoc" {
  for_each       = { for k, v in aws_subnet.eks_subnets : k => v if !v.map_public_ip_on_launch }
  subnet_id      = each.value.id
  route_table_id = aws_route_table.eks_private_route_table[each.key].id
}
