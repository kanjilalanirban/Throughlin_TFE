# Throughlin TFE

Terraform-managed AWS infrastructure for **Company Brain** (Phase 0).

Application code lives in the sibling repo: [Throughlin_app](https://github.com/kanjilalanirban/Throughlin_app).

## Quick start

```bash
# One-time per machine
brew install terraform tflint awscli

# AWS auth via SSO
aws sso login --profile companybrain-phase0

# Plan
cd infra/environments/phase0
terraform init
terraform plan
```

## Conventions, scope, and cross-repo contract

See [CLAUDE.md](CLAUDE.md) and [docs/infrastructure.md](docs/infrastructure.md).

For shared product/architecture/security docs and the ADR history, see [Throughlin_app/docs](https://github.com/kanjilalanirban/Throughlin_app/tree/main/docs).
