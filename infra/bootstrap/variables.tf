variable "region" {
  description = "AWS region for all bootstrap resources."
  type        = string
  default     = "ca-central-1"
}

variable "github_org" {
  description = "GitHub organization or user that owns the repos. Used in OIDC trust policy."
  type        = string
  default     = "kanjilalanirban"
}

variable "github_repo_tfe" {
  description = "Name of the Terraform infrastructure repo (without org prefix)."
  type        = string
  default     = "Throughlin_TFE"
}

variable "github_repo_app" {
  description = "Name of the application repo (without org prefix). Used by the backend-image build workflow's role."
  type        = string
  default     = "Throughlin_app"
}

variable "state_bucket_name" {
  description = "Name of the Terraform state bucket. Must be globally unique. Do not change after bootstrap."
  type        = string
  default     = "companybrain-tf-state"
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking."
  type        = string
  default     = "companybrain-tf-locks"
}
