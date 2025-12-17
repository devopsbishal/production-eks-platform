# ACM Certificate Module

This module creates an AWS Certificate Manager (ACM) certificate with automatic DNS validation via Route53.

## Features

- **Automatic DNS Validation**: Creates Route53 CNAME records for certificate validation
- **Wildcard Support**: Supports wildcard certificates (e.g., `*.eks.example.com`)
- **Subject Alternative Names**: Include multiple domains in one certificate
- **Deduplication**: Handles shared validation records for wildcard + base domain
- **Terraform-managed**: Full lifecycle management including validation

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    ACM Certificate Flow                          │
└─────────────────────────────────────────────────────────────────┘

   ┌─────────────┐      ┌─────────────┐      ┌─────────────────┐
   │   Request   │ ──── │   Create    │ ──── │   Certificate   │
   │ Certificate │      │ DNS Record  │      │   Validated     │
   └─────────────┘      └─────────────┘      └─────────────────┘
         │                    │                      │
         ▼                    ▼                      ▼
   *.eks.example.com    Route53 CNAME         Ready for ALB
   eks.example.com      Validation Record     
```

## Usage

### Basic Usage

```hcl
module "acm_certificate" {
  source = "../../modules/acm"

  domain_name     = "*.eks.example.com"
  route53_zone_id = module.route53_zone.zone_id

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

### With Subject Alternative Names

```hcl
module "acm_certificate" {
  source = "../../modules/acm"

  domain_name               = "*.eks.example.com"
  subject_alternative_names = ["eks.example.com"]
  route53_zone_id           = module.route53_zone.zone_id

  tags = {
    Name        = "eks-wildcard-cert"
    Environment = "production"
  }
}
```

### Using Certificate with ALB Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    alb.ingress.kubernetes.io/certificate-arn: ${module.acm_certificate.certificate_arn}
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS": 443}]'
spec:
  ingressClassName: alb
  rules:
    - host: app.eks.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app
                port:
                  number: 80
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 5.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.0 |

## Resources

| Name | Type |
|------|------|
| aws_acm_certificate.this | resource |
| aws_acm_certificate_validation.this | resource |
| aws_route53_record.validation | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| domain_name | Primary domain name for the certificate | `string` | n/a | yes |
| route53_zone_id | Route53 hosted zone ID for DNS validation | `string` | n/a | yes |
| subject_alternative_names | Additional domain names (SANs) to include | `list(string)` | `[]` | no |
| tags | Tags to apply to the certificate | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| certificate_arn | ARN of the validated ACM certificate |
| certificate_id | ID of the ACM certificate |
| domain_name | Primary domain name of the certificate |
| validation_method | Validation method used (DNS) |

## How DNS Validation Works

1. **Certificate Request**: ACM generates a unique CNAME record requirement
2. **Route53 Record**: Terraform creates the validation CNAME in your hosted zone
3. **Validation**: ACM verifies the record exists and validates ownership
4. **Certificate Issued**: Certificate becomes active (typically 1-5 minutes)

### Wildcard + Base Domain Sharing

When you create a certificate for both `*.eks.example.com` and `eks.example.com`, they share the **same validation CNAME record**. This module handles the deduplication automatically using `tolist()[0]`.

## Troubleshooting

### Certificate Stuck in "Pending Validation"

```bash
# Check Route53 for the validation record
aws route53 list-resource-record-sets \
  --hosted-zone-id Z0081311271HG9FOF9BEE \
  --query "ResourceRecordSets[?Type=='CNAME']"
```

**Causes:**
- Route53 hosted zone not receiving queries (NS delegation issue)
- Validation record not created
- TTL not propagated yet

### Duplicate Record Error

If you see "Tried to create resource record set but it already exists":

1. The module uses `allow_overwrite = true` to handle this
2. If issue persists, manually delete the validation record and re-apply

### Certificate Not Usable

Ensure `aws_acm_certificate_validation` completes before using the certificate:

```hcl
# Use certificate_arn from validation resource, not certificate resource
alb_certificate_arn = module.acm_certificate.certificate_arn  # This waits for validation
```

## Best Practices

1. **Use Wildcard Certificates**: Reduces certificate management overhead
2. **Include Base Domain**: Add `example.com` as SAN with `*.example.com`
3. **Terraform Dependencies**: Use `depends_on` when needed for ALB/Ingress
4. **Certificate Expiry**: ACM auto-renews certificates before expiry
5. **Region Awareness**: For CloudFront, certificates must be in `us-east-1`

## Cost

- ACM certificates are **free** for use with AWS services (ALB, CloudFront, API Gateway)
- No charge for certificate issuance or renewal

## Related Modules

- [route53-zone](../route53-zone/) - Creates hosted zone for domain
- [aws-load-balancer-controller](../aws-load-balancer-controller/) - Creates ALB using the certificate
- [external-dns](../external-dns/) - Auto-manages DNS records for services
