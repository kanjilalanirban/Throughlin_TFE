output "endpoint" {
  description = "Hostname:port of the RDS instance."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname of the RDS instance (no port)."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Postgres port."
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Initial database name."
  value       = aws_db_instance.this.db_name
}

output "master_username" {
  description = "Master DB username."
  value       = aws_db_instance.this.username
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret RDS auto-created for the master password. The app uses this to fetch credentials at startup."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "parameter_group_name" {
  description = "Custom parameter group name (Postgres 16 + pgvector preload)."
  value       = aws_db_parameter_group.this.name
}
