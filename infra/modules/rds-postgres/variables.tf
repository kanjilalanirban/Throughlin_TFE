variable "name_prefix" {
  description = "Prefix for resource names (e.g. \"companybrain-phase0\")."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs across two AZs (RDS subnet group requirement)."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "RDS subnet group requires subnets in at least two AZs."
  }
}

variable "security_group_id" {
  description = "Security group to attach to the RDS instance."
  type        = string
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  description = "Allocated storage in GB."
  type        = number
  default     = 20
}

variable "engine_version" {
  description = "Postgres major.minor version. Must be one of the versions returned by `aws rds describe-db-engine-versions --engine postgres`. Keep aligned with the pgvector-supported list."
  type        = string
  default     = "16.10"
}

variable "database_name" {
  description = "Name of the initial database created in the instance."
  type        = string
  default     = "companybrain"
}

variable "master_username" {
  description = "RDS master username. Password is auto-generated and stored in Secrets Manager."
  type        = string
  default     = "companybrain"
}
