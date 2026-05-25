# rds-postgres

Phase 0 Postgres instance: single-AZ `db.t4g.micro`, 20 GB gp3, pgvector-ready.

## Ephemeral model implications

- `manage_master_user_password = true` — RDS creates a fresh secret on every `make up` and destroys it with the instance on `make down`. No orphaned credentials.
- `skip_final_snapshot = true`, `backup_retention_period = 0`, `delete_automated_backups = true` — destroy is fast (~3-5 min instead of 15+ for snapshot creation).
- `deletion_protection = false` — `make down` must succeed unattended.
- `apply_immediately = true` — no maintenance-window waiting; changes happen now.

## pgvector

`pgvector` is on AWS RDS Postgres 16's extension allowlist. The extension itself is **not enabled by Terraform** — it requires a `CREATE EXTENSION vector;` statement against the running database. The app's first Alembic migration handles this:

```python
# backend/alembic/versions/0001_init.py
op.execute("CREATE EXTENSION IF NOT EXISTS vector;")
```

`make migrate` (in the app repo) runs after `make up` (in this repo) and applies the migration.

## SSL

`rds.force_ssl = 1` is set in the parameter group. The app's database URL must use `sslmode=require`:

```
postgresql+psycopg://user:pass@host:5432/db?sslmode=require
```

The RDS root CA certificate bundle is preinstalled in the official Python image — no extra config needed beyond `sslmode=require`.

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `name_prefix` | Resource name prefix | (required) |
| `subnet_ids` | Private subnet IDs across ≥ 2 AZs | (required) |
| `security_group_id` | RDS security group | (required) |
| `instance_class` | RDS instance class | `db.t4g.micro` |
| `allocated_storage_gb` | Storage in GB | `20` |
| `engine_version` | Postgres version | `16.3` |
| `database_name` | Initial database name | `companybrain` |
| `master_username` | Master username | `companybrain` |

## Outputs

`endpoint`, `address`, `port`, `database_name`, `master_username`, `master_user_secret_arn`, `parameter_group_name`.
