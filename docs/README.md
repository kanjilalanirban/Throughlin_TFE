# Throughlin TFE Docs

This repo owns infra docs only. Shared product, architecture, security, and ADR docs live in the App repo to keep them with the team that touches them most often.

## Owned here

- [infrastructure.md](infrastructure.md) — Terraform conventions, AWS account layout, CI/CD, observability, cost discipline.
- [decisions/](decisions/) — Infra-only ADRs. Cross-link to App ADRs where relevant.

## Pointers (live in [Throughlin_app](https://github.com/kanjilalanirban/Throughlin_app))

- `docs/architecture.md` — System architecture, AWS services, request flows.
- `docs/data-model.md` — The four primitives, schema details.
- `docs/inference.md` — Prompt design, retrieval, scoring.
- `docs/integrations.md` — Jira, GitHub, HRIS adapter patterns.
- `docs/security.md` — Phase 0 security posture, hardening checklist.
- `docs/decisions/` — Product and app-level ADRs (e.g., 0001 — bootstrap phase 0 scope).
- `docs/runbook.md` — Deploy/rollback/debug procedures (lives with app for accessibility, even infra entries).
