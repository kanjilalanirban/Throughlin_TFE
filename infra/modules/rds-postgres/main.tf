resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-rds"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.name_prefix}-rds-subnet-group"
  }
}

# A custom parameter group is needed to preload pg_stat_statements and to
# allow the app to CREATE EXTENSION vector at startup.
resource "aws_db_parameter_group" "this" {
  name        = "${var.name_prefix}-pg16-pgvector"
  family      = "postgres16"
  description = "Postgres 16 with pgvector preload + shared_preload_libraries."

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  # Allow extensions from the rds-superuser; pgvector is on the RDS allowlist.
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = "${var.name_prefix}-pg16-pgvector"
  }
}

resource "aws_db_instance" "this" {
  identifier = "${var.name_prefix}-pg"

  engine            = "postgres"
  engine_version    = var.engine_version
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage_gb
  storage_type      = "gp3"
  storage_encrypted = true
  db_name           = var.database_name
  username          = var.master_username

  # Auto-generate the master password into a fresh Secrets Manager secret
  # scoped to this RDS instance's lifecycle. On `make down` the secret goes
  # too (no orphaned credentials).
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false

  # Ephemeral model: don't snapshot on destroy. App reloads seed data
  # on every `make up`.
  skip_final_snapshot      = true
  delete_automated_backups = true
  backup_retention_period  = 0
  deletion_protection      = false

  # Faster destroy by skipping the final snapshot wait.
  apply_immediately = true

  performance_insights_enabled = false
  monitoring_interval          = 0

  tags = {
    Name = "${var.name_prefix}-pg"
  }
}
