# Route53 Zone Module

This module creates a Route53 hosted zone for subdomain delegation.

## Purpose

Creates a Route53 hosted zone that can be used with External DNS to automatically manage DNS records for Kubernetes Ingress resources. This module is designed for subdomain delegation from an external DNS provider (e.g., Cloudflare).

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Primary DNS (Cloudflare)                      │
│                    rentalhubnepal.com                            │
│                                                                  │
│    NS records for eks.rentalhubnepal.com → Route53 NS servers   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    AWS Route53 Hosted Zone                       │
│                    eks.rentalhubnepal.com                        │
│                                                                  │
│    A record: app.eks.rentalhubnepal.com → ALB IP                │
│    A record: api.eks.rentalhubnepal.com → ALB IP                │
│    (Managed by External DNS)                                     │
└─────────────────────────────────────────────────────────────────┘
```

## Usage

```hcl
module "route53_zone" {
  source = "../../modules/route53-zone"

  domain_name = "eks.example.com"
  environment = "dev"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `domain_name` | The subdomain to create hosted zone for | `string` | n/a | yes |
| `environment` | Environment name (dev, staging, prod) | `string` | `"dev"` | no |
| `resource_tag` | Common tags for all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `zone_id` | Route53 hosted zone ID |
| `name_servers` | NS records to add in primary DNS provider |
| `domain_name` | Domain name of the hosted zone |
| `arn` | ARN of the hosted zone |

## Post-Deployment Steps

After running `terraform apply`, you must configure subdomain delegation:

1. Get the name servers:
   ```bash
   terraform output route53_name_servers
   ```

2. Add NS records in your primary DNS provider (e.g., Cloudflare):
   - Type: `NS`
   - Name: `eks` (just the subdomain prefix)
   - Content: Each Route53 name server (4 records total)

3. Verify delegation:
   ```bash
   dig NS eks.example.com +short
   ```

## Why Subdomain Delegation?

- **Keep primary DNS provider**: No need to migrate entire domain to Route53
- **Separation of concerns**: AWS resources use Route53, other records stay in Cloudflare
- **Cost effective**: Only pay for Route53 records you need
- **External DNS compatible**: Works seamlessly with External DNS controller
