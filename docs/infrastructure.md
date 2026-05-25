# Infrastructure

Read this when writing Terraform, configuring AWS, or working with CI/CD.

## Operating Model — Pure-Ephemeral Stack

Phase 0 runs the entire AWS application stack only while we're actively working on it. There is no always-on production. See ADR [0002 — ephemeral AWS stack](https://github.com/kanjilalanirban/Throughlin_app/blob/main/docs/decisions/0002-ephemeral-aws-stack.md) for the rationale.

### The lifecycle

```
make up      # provision stack from zero (~10-15 min)
... work ... # bring app up, run integrations, demo, eval
make down    # destroy stack (~5-10 min). Everything ephemeral is gone.
```

`make up` is `terraform apply` plus a post-step that triggers the app repo's `make migrate seed`. `make down` is `terraform destroy` of the ephemeral state only — it cannot touch bootstrap.

### The two layers

| Layer | Lifecycle | Contents | Cost |
|-------|-----------|----------|------|
| **Bootstrap (always-on)** | Created **once**, by hand. Never destroyed. | TF state bucket, lock table, IAM Identity Center, GitHub OIDC provider, ECR repos | ~$1-5/month idle |
| **Ephemeral (on/off)** | Created by `make up`, destroyed by `make down` | Everything else: VPC, NAT GW, RDS, Fargate, ALB, Lambdas, Cognito, S3 raw, frontend bucket, EventBridge, CloudWatch log groups | ~$5-15 per working day |

These layers have **separate Terraform state files**. Bootstrap state lives in `infra/bootstrap/terraform.tfstate.d/` (also in S3, but in a distinct path). The ephemeral environment state lives at `s3://companybrain-tf-state/phase0/terraform.tfstate`. This is not optional — mixing them makes `make down` capable of nuking bootstrap, which would brick the next bring-up.

### Rules

- **No resource may be added to the ephemeral stack that holds data we'd cry over losing.** If it must persist, it goes in bootstrap (and rejustify why).
- **No Terraform code may assume the previous run's state survives.** Bring-up always starts from zero.
- **Keep `make up` fast.** Anything that adds minutes is a tax paid every session. Push back on it. Particularly: no CloudFront (15-20 min propagation), no ACM DNS validation (5+ min), no RDS Multi-AZ (slower provisioning).
- **`make down` must be safe to run blindly at end of day.** No prompts, no "are you sure," and no path that can reach bootstrap.

## AWS Account Layout

- **One AWS account** for Phase 0, inside AWS Organizations.
- **Why Organizations with one account?** So adding a separate `prod` account in Phase 1 is a config change, not a migration. Cost: zero.
- **Root user**: locked down with hardware MFA after initial setup. Credentials sealed in a password manager. Never used for daily work.
- **Team access**: IAM Identity Center (formerly AWS SSO). Permission sets per role. MFA enforced.
- **No IAM users for humans.** Period.

## Terraform Conventions

### Layout
```
infra/
├── bootstrap/                  # ALWAYS-ON. Created once, by hand. Documented here.
│   ├── tf-state-bucket.tf      # S3 state bucket + DynamoDB lock table
│   ├── github-oidc.tf          # GitHub OIDC provider + per-repo IAM roles
│   ├── ecr.tf                  # ECR repos for backend + each ingester Lambda
│   └── README.md               # "These were created by hand; here's how to recreate."
├── modules/                    # Reusable building blocks (ephemeral)
│   ├── vpc/
│   ├── rds-postgres/
│   ├── fargate-service/
│   ├── lambda-ingester/
│   └── frontend-static/
└── environments/
    └── phase0/                 # The ephemeral stack
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf          # Pushed to SSM so the app repo can read
        ├── backend.tf          # Remote state at s3://.../phase0/
        ├── versions.tf
        └── terraform.tfvars.example
```

### Remote state
- **Backend:** S3 + DynamoDB locking.
- **Bucket:** `companybrain-tf-state` (versioned, SSE-S3, public access fully blocked).
- **Lock table:** `companybrain-tf-locks`.
- **Region:** `ca-central-1`.
- **State paths:**
  - Bootstrap: `s3://companybrain-tf-state/bootstrap/terraform.tfstate`
  - Phase 0 ephemeral: `s3://companybrain-tf-state/phase0/terraform.tfstate`

### Tagging discipline
Every resource gets these tags (enforce via provider `default_tags`):
```hcl
default_tags {
  tags = {
    App         = "mv01throu"     # project identifier, applied to every resource
    Project     = "companybrain"
    Environment = "phase0"
    ManagedBy   = "terraform"
    CostCenter  = "phase0"
    Lifecycle   = "ephemeral"     # or "bootstrap" in the bootstrap layer
  }
}
```

**Tag rules:**
- `App = "mv01throu"` is the **global project-identifying tag** and goes on every resource without exception. It is used for cost reporting, audits, and IAM conditions that scope access to project-owned resources. `App` is the AWS-idiomatic key (per Well-Architected tagging guidance) and does not collide with AWS's special `Name` tag, which is reserved for per-resource display labels like `companybrain-phase0-api-alb`. A resource may legitimately carry both: `App` (project-wide) and `Name` (resource-specific).
- `Lifecycle` is what makes "how much am I spending while idle?" answerable in Cost Explorer.
- Cost Explorer should be pinned to filter on `App=mv01throu` first; this is the broadest and most reliable scope for project spend.
- **Activate `App` as a Cost Allocation Tag** in the AWS Billing console (one-time, takes ~24h to start showing data). This is the step that makes `App` filterable in Cost Explorer — adding the tag in `default_tags` alone is not enough.

**Compliance check:** the `pr.yml` workflow runs a guard that fails the build if any new resource block in a `.tf` file omits an `App` tag (either via `default_tags` inheritance or an explicit `tags` block). The check is dumb-grep-level for Phase 0; it can be promoted to a `tflint` custom rule later.

### Module conventions
- Each module has `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, and a `README.md`.
- Variables have descriptions and types. No mystery inputs.
- Outputs document what they expose. Other modules consume outputs, never internal resource IDs.
- Modules are versioned via git tags once stable. Pin module sources to tags, not branches.

### Naming
- Resources: `{project}-{environment}-{purpose}`. Example: `companybrain-phase0-api-alb`.
- Terraform resource names: snake_case. Example: `resource "aws_lb" "api"`.

### Outputs go to SSM (the cross-repo contract)
The phase0 environment publishes its outputs to AWS SSM Parameter Store so the app repo can consume them without sharing Terraform state. Pattern:

```hcl
resource "aws_ssm_parameter" "rds_endpoint" {
  name  = "/companybrain/phase0/rds/endpoint"
  type  = "String"
  value = module.rds.endpoint
}
```

Standard parameter paths (keep this list updated as outputs are added):
- `/companybrain/phase0/rds/endpoint`
- `/companybrain/phase0/rds/secret_arn`
- `/companybrain/phase0/alb/dns_name`
- `/companybrain/phase0/cognito/user_pool_id`
- `/companybrain/phase0/cognito/client_id`
- `/companybrain/phase0/ecr/backend_uri`
- `/companybrain/phase0/s3/raw_bucket`
- `/companybrain/phase0/s3/frontend_bucket`

### Drift management
- **No clickops.** If you change anything in the AWS console, immediately write the Terraform and apply it.
- Drift detection is **less important** in this model because the stack is recreated from scratch on every `make up` — drift dies a natural death. But changes made manually mid-session won't survive `make down`, so still: write the code.

## CI/CD (GitHub Actions)

### Auth: OIDC, not access keys
- GitHub OIDC identity provider configured in IAM (one-time setup, documented in `bootstrap/github-oidc.tf`).
- IAM role with trust policy scoped to this repo. Plan-only branches assume a read-only role; `main` assumes the apply role.
- Workflows authenticate via `aws-actions/configure-aws-credentials@v4` with `role-to-assume` and `audience: sts.amazonaws.com`.
- **Never store `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` in GitHub Secrets.**

### Workflows (this repo)

| File | Trigger | What it does |
|------|---------|--------------|
| `pr.yml` | PR opened/updated | `terraform fmt -check`, `validate`, `plan`. Posts plan as PR comment. |
| `drift-check.yml` | Weekly cron | Runs `plan` against current bootstrap and any live ephemeral state; alerts on non-empty plan. |

**There is no `apply.yml` that auto-applies on push to main in Phase 0.** Apply is triggered by a human running `make up` locally. This matches the ephemeral model: stack lifecycle is a human action, not a git event.

### Workflows (in the app repo)

For completeness — these belong to `Throughlin_app` but the seam matters here:

| File | Trigger | What it does |
|------|---------|--------------|
| `pr.yml` | PR opened/updated | Lint, typecheck, unit tests (backend + frontend) |
| `backend-image.yml` | Push to `main` (paths: `backend/**`, `ingesters/**`) | Build container, push to ECR with both `latest` and `sha-{commit}` tags |
| `frontend-build.yml` | Push to `main` (paths: `frontend/**`) | Build static bundle, upload artifact (consumed by `make up`) |

Backend image build is the only thing that auto-runs on push. The ephemeral stack picks up `latest` at the next `make up`.

### Branch protection on `main`
- Require PR review.
- Require status checks: lint, typecheck, tests, `terraform plan`.
- Require branches to be up to date before merge.
- Disallow direct pushes.

### Secrets in CI
- App secrets (Anthropic key, OAuth secrets) live in AWS Secrets Manager, **not** GitHub Secrets.
- The only thing in GitHub Secrets is the IAM role ARN to assume (and that's not technically a secret).

## Local Development

In the ephemeral model, **local is the default**. AWS is only brought up when you need the full stack (Cognito flows, Lambda execution, IAM-scoped behavior, end-to-end demos).

### Required tools
- Python 3.12+
- Node.js 20+
- `uv` (Python package manager)
- `pnpm` (Node package manager)
- Docker (for local Postgres)
- Terraform 1.6+
- AWS CLI v2
- `gh` (GitHub CLI)

### Local Postgres
See [Throughlin_app/docker-compose.yml](https://github.com/kanjilalanirban/Throughlin_app/blob/main/docker-compose.yml). `docker compose up -d postgres` brings up Postgres 16 with pgvector.

### Environment variables (local only)
See the app repo's `backend/.env.example`. AWS deployments load everything from Secrets Manager at app startup — never env vars.

## Observability

### Stack
- **Instrumentation:** OpenTelemetry SDK (vendor-neutral) in backend and ingesters.
- **Export:** AWS Distro for OpenTelemetry (ADOT) collector → CloudWatch Logs, CloudWatch Metrics, X-Ray.
- **Frontend:** error tracking via a thin wrapper around `window.onerror`; sent to a backend endpoint that logs to CloudWatch. No third-party tracker in Phase 0.

### What to instrument
- Auto-instrument: FastAPI, SQLAlchemy, httpx, Lambda runtime.
- Manual spans (required):
  - Every Claude API call (use-case, model, tokens, cost).
  - Every ingestion run (source, duration, record count, errors).
  - The retrieval pipeline (vector search, structured filter, total signals returned).
- Standard span attributes everywhere: `tenant.org_id`, `user.id`, `request.id`.

### Telemetry lifecycle
CloudWatch log groups, X-Ray traces, and CloudWatch metrics are **ephemeral**: they die with the stack. If you need to keep something across sessions (an interesting trace, a cost breakdown), export it to S3 or a local file before `make down`.

### Alarms (CloudWatch)
- Billing: $50, $100, $200 (revised downward to match ephemeral cost shape).
- 5xx error rate on ALB > 5% over 5 min — only meaningful while the stack is up; auto-cleans on teardown.
- Lambda failures > 3 in 15 min (any function).
- RDS CPU > 80% for 15 min.
- Claude API error rate > 10% over 5 min.

## Cost Discipline

### Tracking
- Cost Explorer dashboard pinned, filtered to `Project=companybrain`.
- Use the `Lifecycle` tag to split bootstrap-vs-ephemeral spend.
- Weekly cost review (15 min, every Monday) — primarily to confirm idle spend is staying near zero.

### Known cost levers
- **Anthropic API**: the variable. Track per-feature; audit if any feature > 20% of working-period spend.
- **NAT Gateway**: ~$32/month if always-on. **Ephemeral model eliminates this**: it's only billed for the hours `make up` is live. A working day with NAT GW costs ~$1; an idle month costs $0.
- **RDS instance hours**: ditto — only billed while the stack is up.
- **CloudWatch Logs**: log level INFO by default; logs die with the stack so retention isn't a long-term cost concern.
- **ECR storage**: small (~$0.10/GB/month). Tolerable; image cleanup can wait.

### Cost guardrails
- Anomaly detection enabled (alerts on $25+ deltas — tighter than the original $50 because total spend is lower).
- Budget actions email at 80%/100%/120% of $75 monthly budget (revised from $300 because the ephemeral model targets ~$30-60/month).
- **Forgotten-stack alarm**: CloudWatch alarm fires if the ephemeral state file shows resources that have existed for > 24 hours. Means someone forgot to `make down`.

## Documentation Requirements

### ADRs
Every meaningful technical choice gets a 1-page ADR. Infra-specific ADRs live in `docs/decisions/` in this repo; product/app ADRs live in `Throughlin_app/docs/decisions/`. Cross-link both ways. Format:

```
# NNNN. Title

Date: YYYY-MM-DD
Status: Proposed | Accepted | Superseded by NNNN

## Context
What's the situation?

## Decision
What did we decide?

## Consequences
What does this mean? What did we trade off?
```

### Runbook
`Throughlin_app/docs/runbook.md` is the deploy/rollback/debug bible — lives in the app repo for accessibility (the team that reads it daily). Update it when you change any operational flow. Treat it as code, not a wiki.

The runbook should always cover, at minimum:
- How to bring the stack up and tear it down (`make up` / `make down` mechanics, what to check).
- What to do if `make up` partially fails (state cleanup, common stuck resources).
- What to do if `make down` partially fails (orphan resource scan, manual cleanup steps).
- How to rotate Anthropic, Jira, GitHub credentials (the secret containers persist via bootstrap; values are populated out-of-band).
