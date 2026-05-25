# lambda-ingester

Generic Lambda module used for each ingester (`jira`, `github`, `hris`) and the `normalizer`. Container-image based, VPC-attached, optionally scheduled via EventBridge.

## Why container images for Lambda?

Phase 0 ingesters share code with the FastAPI backend (the adapters live in `backend/app/integrations/`). Container packaging lets us reuse the backend's `uv`-managed Python environment without maintaining a separate `requirements.txt` per Lambda. The app repo's `backend-image.yml` workflow builds one image per Lambda from the same Dockerfile family.

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `name_prefix` | Resource prefix | (required) |
| `ingester_name` | `jira` / `github` / `hris` / `normalizer` | (required) |
| `image_uri` | ECR image URI; placeholder if empty | `""` |
| `schedule_expression` | EventBridge schedule; empty = no schedule (the normalizer uses S3 triggers) | `""` |
| `subnet_ids` | Private subnets for VPC attachment | (required) |
| `security_group_id` | Lambda SG | (required) |
| `memory_mb` | Memory in MB | `512` |
| `timeout_seconds` | Timeout in seconds | `300` |
| `raw_bucket_arn` | S3 raw-data bucket ARN | (required) |
| `secret_arns_to_read` | Secrets the function may read | `[]` |
| `ssm_parameter_arns_to_read` | SSM parameters the function may read | `[]` |
| `log_retention_days` | Log retention | `7` |
| `environment_variables` | Extra env vars | `{}` |

## Outputs

`function_name`, `function_arn`, `role_arn`, `log_group_name`.

## Scheduling examples

```hcl
# Jira: every 30 minutes
schedule_expression = "rate(30 minutes)"

# GitHub: every 30 minutes
schedule_expression = "rate(30 minutes)"

# HRIS: daily at 06:00 UTC
schedule_expression = "cron(0 6 * * ? *)"

# Normalizer: no EventBridge — S3 event source, wired separately in phase0/main.tf
schedule_expression = ""
```

## Phase 0 behavior

Because the stack is ephemeral, scheduled Lambdas only run while the stack is up. A 30-minute Jira schedule may fire 0-3 times in a typical working session. The first invocation after `make up` may have a cold-start that includes ENI provisioning (~10-15s for VPC-attached Lambdas) — acceptable.

The normalizer Lambda has `schedule_expression = ""` and is triggered by S3 PutObject events on the raw bucket. The S3 notification is wired in `phase0/main.tf`, not in this module (because it's a per-environment concern, not a per-Lambda one).
