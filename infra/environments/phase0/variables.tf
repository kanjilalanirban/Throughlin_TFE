variable "region" {
  description = "AWS region."
  type        = string
  default     = "ca-central-1"
}

variable "name_prefix" {
  description = "Prefix for all resource names. Do not change after first apply."
  type        = string
  default     = "companybrain-phase0"
}

variable "backend_image_tag" {
  description = "Image tag to deploy for the backend container. Defaults to `latest`; override to pin a specific commit SHA."
  type        = string
  default     = "latest"
}

variable "ingester_image_tags" {
  description = "Image tag per ingester. Empty string (default) means use the upstream Lambda Python placeholder image (the function will fail at invocation until a real image is pushed). Set to a real tag (e.g. \"latest\" or a commit SHA) once the app repo's CI has pushed images."
  type        = map(string)
  default = {
    jira       = ""
    github     = ""
    hris       = ""
    normalizer = ""
  }
}

variable "backend_image_exists" {
  description = "Whether a real backend image exists in ECR. True (default) once the app repo's CI has pushed at least one image. Override to false ONLY if you want to bring up infra before any image is pushed."
  type        = bool
  default     = true
}

variable "jira_schedule" {
  description = "EventBridge schedule for the Jira ingester."
  type        = string
  default     = "rate(30 minutes)"
}

variable "github_schedule" {
  description = "EventBridge schedule for the GitHub ingester."
  type        = string
  default     = "rate(30 minutes)"
}

variable "hris_schedule" {
  description = "EventBridge schedule for the HRIS ingester (rarely fires in a typical session)."
  type        = string
  default     = "cron(0 6 * * ? *)"
}
