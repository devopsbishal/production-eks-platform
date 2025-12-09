# Route53 Hosted Zone for subdomain (delegated from Cloudflare)
# Example: aws.yourdomain.com
resource "aws_route53_zone" "eks" {
  name    = var.domain_name
  comment = "Managed by Terraform - EKS platform subdomain"

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.domain_name}-hosted-zone"
      Environment = var.environment
    }
  )
}

# Note: NS records are automatically created by Route53
# You need to add these NS records in Cloudflare to delegate the subdomain
# Use: terraform output name_servers
