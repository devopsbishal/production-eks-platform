output "zone_id" {
  description = "Route53 hosted zone ID"
  value       = aws_route53_zone.eks.zone_id
}

output "name_servers" {
  description = "Name servers for the hosted zone - ADD THESE TO CLOUDFLARE as NS records"
  value       = aws_route53_zone.eks.name_servers
}

output "domain_name" {
  description = "Domain name of the hosted zone"
  value       = aws_route53_zone.eks.name
}

output "arn" {
  description = "ARN of the hosted zone"
  value       = aws_route53_zone.eks.arn
}
