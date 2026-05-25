variable "name_prefix" {
  description = "Prefix for resource names (e.g. \"companybrain-phase0\")."
  type        = string
}

variable "ingester_name" {
  description = "Logical name of the ingester (jira | github | hris | normalizer). Used in function name, log group, and ECR repo lookup."
  type        = string

  validation {
    condition     = contains(["jira", "github", "hris", "normalizer"], var.ingester_name)
    error_message = "ingester_name must be one of: jira, github, hris, normalizer."
  }
}

variable "image_uri" {
  description = "Full ECR image URI for this ingester. If empty, the function is created with a placeholder and will fail at invocation time until a real image is pushed."
  type        = string
  default     = ""
}

variable "schedule_expression" {
  description = "EventBridge schedule expression (e.g. \"rate(30 minutes)\" or \"cron(0 6 * * ? *)\"). Set to empty string to disable scheduling (e.g. the normalizer, which is triggered by S3 events instead)."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Private subnet IDs the Lambda should attach to (for RDS access)."
  type        = list(string)
}

variable "security_group_id" {
  description = "Lambda security group ID."
  type        = string
}

variable "memory_mb" {
  description = "Lambda memory in MB."
  type        = number
  default     = 512
}

variable "timeout_seconds" {
  description = "Lambda timeout in seconds. Phase 0 keeps ingestion short."
  type        = number
  default     = 300
}

variable "raw_bucket_arn" {
  description = "ARN of the S3 raw-data bucket the ingester writes to."
  type        = string
}

variable "secret_arns_to_read" {
  description = "Secrets Manager ARNs the function may read."
  type        = list(string)
  default     = []
}

variable "ssm_parameter_arns_to_read" {
  description = "SSM Parameter Store ARNs the function may read."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "CloudWatch log retention."
  type        = number
  default     = 7
}

variable "environment_variables" {
  description = "Extra environment variables for the Lambda function."
  type        = map(string)
  default     = {}
}
