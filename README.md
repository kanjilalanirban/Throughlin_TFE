# Throughlin TFE

Terraform-managed AWS infrastructure for **Company Brain** (Phase 0).

Application code: [Throughlin_app](https://github.com/kanjilalanirban/Throughlin_app).

## Status

| Layer | State |
|---|---|
| Bootstrap (always-on, ~$1-5/mo) | ✓ Applied — state bucket, OIDC, IAM roles, ECR repos, secret containers |
| Ephemeral phase0 stack | Brought up/down by `make up` / `make down`. See lifecycle below. |
| GitHub Actions | ✓ `pr.yml`, `apply.yml`, `destroy.yml`, `drift-check.yml` |

## Lifecycle (the supported workflow)

Both commands are idempotent. Pick whichever path is easier.

### Bring up

**From GitHub UI** (recommended — no laptop AWS auth required):

1. Go to **Actions** → **"Apply (manual — make up)"** → **Run workflow**
2. Type `APPLY` in the confirm box → Run
3. ~7-10 minutes; ALB DNS + frontend URL printed in the run summary
4. After it finishes, also trigger **"Frontend deploy"** in the app repo so the bundle picks up the new ALB URL

**Locally:**
```bash
aws sso login --profile quantumsmartaws-admin
export AWS_PROFILE=quantumsmartaws-admin

cd Throughlin_TFE
make up                 # ~7-10 min
make outputs            # prints ALB DNS, frontend URL, etc.
```

### Tear down (zero per-hour cost)

**From GitHub UI:**

1. Go to **Actions** → **"Destroy (manual — make down)"** → **Run workflow**
2. Type `DESTROY` → Run
3. ~5-10 min; ephemeral stack is gone

**Locally:**
```bash
cd Throughlin_TFE
make down
```

### What persists after `make down`

Always-on (~$1-5/month):
- TF state bucket + DynamoDB lock table
- ECR repos and the images we've pushed
- IAM Identity Center config + GitHub OIDC provider + 3 CI IAM roles
- Secrets Manager **containers** (Anthropic key value preserved)

What's wiped:
- VPC, NAT GW, RDS (with all data), Fargate, ALB, Cognito user pool **and the `anirbank` user**, S3 raw bucket, frontend bucket, SSM parameters, EventBridge schedules, CloudWatch logs

See [Throughlin_app/docs/runbook.md](https://github.com/kanjilalanirban/Throughlin_app/blob/main/docs/runbook.md) for the full step-by-step including how to re-create the Cognito user and re-seed data after a fresh `make up`.

## What this stack provisions

| Component | Module |
|---|---|
| VPC (2 AZs), NAT GW, IGW, 4 SGs | `modules/vpc` |
| RDS Postgres 16 + pgvector | `modules/rds-postgres` |
| ECS Fargate + ALB (HTTP) | `modules/fargate-service` |
| Lambda ingesters (Jira / GitHub / HRIS / normalizer) | `modules/lambda-ingester` — gated per-ingester on image presence |
| S3 frontend bucket (no CloudFront) | `modules/frontend-static` |
| Cognito user pool + client, S3 raw bucket, 18 SSM parameters | `environments/phase0/main.tf` |

Tagging: every resource carries `App = "mv01throu"` plus standard tags; `Lifecycle = "bootstrap"` vs `Lifecycle = "ephemeral"` segregates the two layers in Cost Explorer.

## Conventions

See [CLAUDE.md](CLAUDE.md) and [docs/infrastructure.md](docs/infrastructure.md).

For shared product / architecture / security docs and ADR history, see [Throughlin_app/docs](https://github.com/kanjilalanirban/Throughlin_app/tree/main/docs).
