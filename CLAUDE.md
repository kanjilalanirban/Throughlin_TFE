# Throughlin TFE — Company Brain Infrastructure

> **This repo holds Terraform-managed AWS infrastructure for Company Brain Phase 0.**
> Application code (backend, frontend, ingesters) lives in the sibling repo `kanjilalanirban/Throughlin_app`.

---

## OPERATING MODEL — READ FIRST

**Phase 0 runs as a pure-ephemeral AWS stack. Nothing is left running between work sessions.**

The lifecycle is:

```
make up      # ~10-15 min: provision stack, migrate DB, load seed data
... work ...
make down    # ~5-10 min: destroy stack. Everything ephemeral is gone.
```

**Nothing in the running stack persists across teardowns.** Database state, ingested raw data, audit log, signals — all wiped on `make down`. Every session starts from a known-good seeded state. This is by design (ADR 0002).

### Always-on (the floor — ~$1-5/month idle)

These resources exist permanently because tearing them down would break the next bring-up:

- Terraform state bucket (`companybrain-tf-state`, S3, versioned)
- Terraform lock table (`companybrain-tf-locks`, DynamoDB)
- IAM Identity Center config and GitHub OIDC provider
- ECR repositories (so container images survive across sessions)

These live in `infra/bootstrap/` (documented; created once by hand) — they are **never** touched by `make down` and **never** in the ephemeral Terraform state.

### Ephemeral (everything else — destroyed on `make down`)

VPC, NAT GW, RDS, Fargate, ALB, Lambdas, Cognito, S3 raw bucket, frontend bucket, CloudWatch log groups, EventBridge schedules.

### Not in Phase 0 at all

- **No domain.** No Route53, no ACM, no CloudFront. Frontend serves from S3 bucket URL or local Vite. Backend on raw ALB DNS.
- **No auto-deploy on push to main.** Container images are built and pushed to ECR by CI; the running stack pulls `latest` on the next `make up`.

### Rules that follow from this

- **Never add a resource to the ephemeral stack that contains data you'd cry over losing.** If it must persist, it goes in the always-on bootstrap layer (and re-justify why).
- **Never write Terraform that assumes the previous run's state is still there.** Bring-up always starts from zero.
- **Keep `make up` fast.** Anything that adds minutes to bring-up time is a tax paid every session. Push back on it.
- **`make down` must be safe to run blindly at end of day.** No prompts, no "are you sure," and definitely no path that could touch always-on resources.

See [docs/infrastructure.md](docs/infrastructure.md) for operational detail, and [Throughlin_app/docs/decisions/0002-ephemeral-aws-stack.md](https://github.com/kanjilalanirban/Throughlin_app/blob/main/docs/decisions/0002-ephemeral-aws-stack.md) for the decision rationale.

---

## Repo Boundary

**In this repo:**
- All Terraform code (modules + environments)
- Bootstrap documentation (one-time manual resources)
- Infra CI/CD workflows (`terraform validate`, `plan`, `apply`)
- The deep-dive `docs/infrastructure.md`

**Not in this repo:**
- FastAPI backend, React frontend, Lambda handler code
- Application-level docs (architecture, data model, inference, integrations, security, ADRs)
- App CI workflows (lint, typecheck, test, container build)

Shared product context (architecture, security, ADR history) lives in `kanjilalanirban/Throughlin_app`. See [docs/README.md](docs/README.md) for the pointer list.

---

## Cross-Repo Coordination

The two repos meet at the AWS account. The contract:

1. **TFE provisions and exposes outputs.** RDS endpoint, ALB DNS, Cognito user pool, ECR repo URI, S3 bucket names, IAM role ARNs, secret ARNs.
2. **Outputs are published to AWS SSM Parameter Store** under `/companybrain/phase0/...` so the app repo's deploy workflows can read them by name (no cross-repo Terraform state sharing).
3. **App secrets are created (empty) by TFE** in Secrets Manager; **values are populated out-of-band** by a human, never via Terraform (so they don't end up in state).
4. **The app repo never runs Terraform.** It reads SSM at deploy time and the running app reads Secrets Manager at startup.

This is the seam. If you're about to break it (e.g., adding a Terraform resource that depends on app code, or having the app provision AWS resources at runtime), stop and reconsider.

---

## Tech Stack

| Layer | Choice |
|-------|--------|
| IaC | Terraform 1.6+ |
| Remote state | S3 (`companybrain-tf-state`) + DynamoDB lock (`companybrain-tf-locks`), region `ca-central-1` |
| Cloud | AWS, single account, region `ca-central-1` (ACM for CloudFront in `us-east-1`) |
| CI/CD | GitHub Actions, OIDC auth (no long-lived AWS keys) |

---

## Essential Commands

```bash
# Lifecycle (from repo root) — primary day-to-day commands
make up                          # Provision the entire stack from zero (~10-15 min)
make down                        # Destroy the entire ephemeral stack (~5-10 min)
make status                      # Is the stack up? What's the ALB DNS? RDS endpoint?
make outputs                     # Dump SSM-published outputs the app repo consumes

# Terraform directly (from infra/environments/phase0/)
terraform init
terraform fmt -recursive ../..
terraform validate
terraform plan
terraform apply                  # Same as `make up` from repo root
terraform destroy                # Same as `make down` from repo root
terraform output

# Linting (from repo root)
tflint
tfsec .                          # advisory locally; gating in CI
```

`make up` and `make down` are the supported interface. Use `terraform` directly only when you need to inspect or debug something specific.

---

## Folder Structure

```
Throughlin_TFE/
├── infra/
│   ├── bootstrap/              # Resources created ONCE, by hand (documentation only)
│   │   ├── tf-state-bucket.tf  # The actual bucket was created manually
│   │   └── github-oidc.tf      # GitHub OIDC provider, likewise
│   ├── modules/                # Reusable building blocks
│   │   ├── vpc/
│   │   ├── rds-postgres/
│   │   ├── fargate-service/
│   │   ├── lambda-ingester/
│   │   └── frontend-static/
│   └── environments/
│       └── phase0/             # The actual stack we deploy
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           ├── backend.tf      # Points to the remote state
│           ├── versions.tf
│           └── terraform.tfvars.example
├── docs/
│   ├── infrastructure.md       # Owned here
│   ├── README.md               # Pointer to shared docs in Throughlin_app
│   └── decisions/              # Infra-only ADRs
└── .github/workflows/
    ├── pr.yml                  # validate + plan on PR
    ├── apply.yml               # apply on push to main (paths: infra/**)
    └── drift-check.yml         # weekly plan on schedule
```

---

## Conventions

### Terraform layout
- Each module has `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, and a `README.md`.
- Variables have descriptions and types. No mystery inputs.
- Outputs are the public API of a module. Other modules consume outputs, never raw resource IDs.
- Modules are versioned via git tags once stable. Pin module sources to tags, not branches.

### Naming
- Resources: `{project}-{environment}-{purpose}` — e.g., `companybrain-phase0-api-alb`.
- Terraform identifiers: snake_case — e.g., `resource "aws_lb" "api"`.

### Tagging (enforce via provider `default_tags`)
```hcl
default_tags {
  tags = {
    App         = "mv01throu"     # project identifier, applied to every resource
    Project     = "companybrain"
    Environment = "phase0"
    ManagedBy   = "terraform"
    CostCenter  = "phase0"
  }
}
```

**Every resource gets `App = "mv01throu"`.** This is non-negotiable — it's the global project-identifying tag used for cost reporting, ownership audits, and IAM policy conditions that scope access to project-owned resources. `App` is the AWS-idiomatic key (Well-Architected guidance) and does not collide with AWS's special `Name` tag, which is used for per-resource display labels like `companybrain-phase0-api-alb`. Resources may carry both: `App = "mv01throu"` (project-wide) and `Name = "companybrain-phase0-api-alb"` (resource-specific).

### Drift management
- **No clickops.** If you change anything in the AWS console manually, immediately write the Terraform and apply it. If you can't, file an issue.
- `drift-check.yml` runs `terraform plan` weekly. Non-empty plan triggers a PR comment / alert.

### Bootstrap is documentation, not code
The `infra/bootstrap/` `.tf` files describe the one-time hand-created resources (state bucket, lock table, GitHub OIDC provider). They are **not applied** — they exist so a future engineer can recreate the bootstrap if needed. Mark them clearly at the top of each file.

### CI auth
- GitHub Actions assume an IAM role via OIDC (`aws-actions/configure-aws-credentials@v4`).
- The role trust policy is scoped to this repo and to `main` for apply, any branch for plan.
- **Never store `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in GitHub Secrets.**

### Secrets in Terraform
- Create Secrets Manager **resources** (the empty container) here. Populate the **value** out-of-band so it never lands in state.
- Never put a secret value in a `.tfvars` file, environment variable, or commit it.

### State hygiene
- Never run `terraform state rm` or `terraform import` casually. Both are recorded in the runbook with rationale before/after.
- Never edit remote state directly via S3.

---

## What's Explicitly Out of Scope for Phase 0

Don't build these unless asked:
- KMS customer-managed keys
- WAF, GuardDuty, Security Hub, AWS Config
- Multi-AZ RDS, read replicas, cross-region snapshot replication
- VPC Flow Logs
- A second environment (no `staging`, no `prod`; just `phase0`)
- A second region
- A custom domain (Route53, ACM, CloudFront — see ADR 0002)
- Auto-deploy on push to main (CI builds images; `make up` pulls them)
- Anything that breaks the pure-ephemeral model (snapshot/restore, long-running cron, persistent data outside the bootstrap layer)

See `docs/infrastructure.md` for the Phase 0 → Phase 1 hardening checklist.

---

## How to Work With This Codebase

1. **Read `docs/infrastructure.md` before adding Terraform.** Conventions are documented; don't reinvent them.
2. **Plan before you code.** For any non-trivial change, write the plan in the PR description first.
3. **Match existing module patterns.** Mirror the structure of an existing module rather than introducing a new shape.
4. **Always run `terraform plan` and read it before `apply`.** No exceptions.
5. **For each meaningful technical decision, write an ADR** in `docs/decisions/`. Cross-link to the App repo's ADRs where relevant.
6. **Update `docs/runbook.md` in the App repo when you change deploy/rollback flow.** The runbook is the single source for ops procedures; it lives with the app for accessibility, even though some entries are infra.

---

## Communication With the Human

- Be concise. No emojis in code, commits, or docs.
- Push back if asked to do something inconsistent with the conventions above.
- When uncertain about Phase 0 scope, ask. Better to ask once than build the wrong thing.
