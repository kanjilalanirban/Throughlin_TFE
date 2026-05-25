variable "name_prefix" {
  description = "Prefix for resource names (e.g. \"companybrain-phase0\")."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (for the ALB)."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs (for the Fargate tasks)."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID for the ALB."
  type        = string
}

variable "fargate_security_group_id" {
  description = "Security group ID for the Fargate tasks."
  type        = string
}

variable "container_image" {
  description = "Full ECR image URI for the backend (e.g. <acct>.dkr.ecr.ca-central-1.amazonaws.com/companybrain-backend:latest). If empty, the service will be created with a placeholder image and you must push a real image before traffic works."
  type        = string
  default     = ""
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8000
}

variable "cpu" {
  description = "Fargate task CPU (units of 1024 = 1 vCPU)."
  type        = number
  default     = 512
}

variable "memory" {
  description = "Fargate task memory in MB."
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Number of tasks to run."
  type        = number
  default     = 1
}

variable "secret_arns_to_read" {
  description = "ARNs of Secrets Manager secrets the task role should be allowed to read (Anthropic, Jira, GitHub, RDS master)."
  type        = list(string)
  default     = []
}

variable "ssm_parameter_arns_to_read" {
  description = "ARNs of SSM parameters the task role should be allowed to read (e.g. the published phase0 outputs)."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "CloudWatch log retention (the group is destroyed on `make down` anyway; this just caps any within-session log volume)."
  type        = number
  default     = 7
}
