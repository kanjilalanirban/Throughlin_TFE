# vpc

Phase 0 VPC: one VPC, two AZs (for the RDS subnet group requirement), one NAT Gateway, and four security groups (`alb`, `fargate`, `rds`, `lambda`) with strict least-privilege rules.

## Why single-AZ compute with two-AZ subnets?

RDS subnet groups require subnets in at least two AZs even when the DB instance itself is single-AZ. We create the second private subnet to satisfy this, but Fargate tasks and NAT live only in AZ #1. Cost: ~$0/month extra (empty subnets are free). Phase 1 will populate the second AZ as part of Multi-AZ RDS.

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `name_prefix` | Prefix for resource names | (required) |
| `cidr_block` | VPC CIDR | `10.20.0.0/16` |
| `availability_zones` | Two AZs to span | `["ca-central-1a", "ca-central-1b"]` |
| `public_subnet_cidrs` | Public subnet CIDRs | `["10.20.0.0/24", "10.20.1.0/24"]` |
| `private_subnet_cidrs` | Private subnet CIDRs | `["10.20.10.0/24", "10.20.11.0/24"]` |

## Outputs

`vpc_id`, `vpc_cidr_block`, `public_subnet_ids`, `private_subnet_ids`, `alb_security_group_id`, `fargate_security_group_id`, `rds_security_group_id`, `lambda_security_group_id`.

## Security-group topology

```
internet ─►  alb_sg  (80)  ─►  fargate_sg (8000)  ─►  rds_sg (5432)
                                       │
                                       ▼
                                  external APIs
                                  (via NAT GW)

                                lambda_sg          ─►  rds_sg (5432)
                                       │
                                       ▼
                                  external APIs
                                  (via NAT GW)
```

ALB accepts HTTP on :80 from anywhere (Phase 0, no domain). Fargate accepts only from ALB SG. RDS accepts only from Fargate or Lambda SGs. Lambdas have no ingress.

## Cost note

- NAT Gateway is the single biggest line item in this module (~$0.045/hr + data transfer). Ephemeral model means it's only billed while the stack is up.
- EIP for NAT is free while attached, $0.005/hr if detached — `make down` releases it cleanly.
