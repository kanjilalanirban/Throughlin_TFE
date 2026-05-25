# fargate-service

ECS Fargate cluster + service + Application Load Balancer for the FastAPI backend.

## What it provisions

- ECS cluster (Container Insights disabled to save cost)
- Task execution role (pull image from ECR, write logs, read secrets) and task role (app-runtime AWS access)
- ECS task definition + service in private subnets
- ALB in public subnets with an HTTP-only listener on `:80` (Phase 0; HTTPS in Phase 1 with a domain)
- Target group with `/health` health check
- CloudWatch log group `/ecs/<name_prefix>-api`

## Phase 0 notes

- **HTTP only** on the ALB. No ACM cert, no HTTPS listener. The single client (the team) reaches the API via the rotating ALB DNS name printed by `make outputs`.
- **Placeholder image**: if `container_image` is empty, the service comes up with `public.ecr.aws/nginx/nginx:stable` so the stack succeeds. Push a real backend image to ECR and re-apply (or wait for it; `desired_count` is 1 so the next task pull picks up `latest`).
- **No auto-scaling.** Single task; manually bump `desired_count` for short-lived load tests.
- **`ignore_changes = [desired_count]`** on the service so manual scale changes don't get reverted by a casual `apply`.

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `name_prefix` | Resource name prefix | (required) |
| `vpc_id` | VPC ID | (required) |
| `public_subnet_ids` | Public subnet IDs for the ALB | (required) |
| `private_subnet_ids` | Private subnet IDs for tasks | (required) |
| `alb_security_group_id` | ALB SG | (required) |
| `fargate_security_group_id` | Fargate SG | (required) |
| `container_image` | Full ECR image URI | `""` (uses nginx placeholder) |
| `container_port` | Container listen port | `8000` |
| `cpu` | Task CPU (256 = 0.25 vCPU) | `512` |
| `memory` | Task memory MB | `1024` |
| `desired_count` | Task count | `1` |
| `secret_arns_to_read` | Secrets Manager ARNs the task may read | `[]` |
| `ssm_parameter_arns_to_read` | SSM parameter ARNs the task may read | `[]` |
| `log_retention_days` | CloudWatch log retention | `7` |

## Outputs

`cluster_arn`, `cluster_name`, `service_name`, `task_role_arn`, `alb_arn`, `alb_dns_name`, `alb_zone_id`, `log_group_name`.

## How the app gets configuration

The app reads `ENVIRONMENT=phase0` and `AWS_REGION` from container env vars. Everything else (DB connection from RDS-created secret, Anthropic API key from bootstrap secret, etc.) is fetched at startup via the task role's permissions on Secrets Manager + SSM. This is intentional: it means the task definition does not need to change on every secret rotation.
