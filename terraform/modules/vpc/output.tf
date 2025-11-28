output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.eks_vpc.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.eks_vpc.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = [for k, v in aws_subnet.eks_subnets : v.id if v.map_public_ip_on_launch]
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = [for k, v in aws_subnet.eks_subnets : v.id if !v.map_public_ip_on_launch]
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = [for nat in aws_nat_gateway.eks_nat_gateway : nat.id]
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = aws_internet_gateway.eks_gw.id
}

output "public_route_table_id" {
  description = "The ID of the public route table"
  value       = aws_route_table.eks_route_table.id
}

output "private_route_table_ids" {
  description = "Map of private route table IDs by subnet key"
  value       = { for k, v in aws_route_table.eks_private_route_table : k => v.id }
}
