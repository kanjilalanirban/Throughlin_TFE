output "state_bucket" {
  description = "Name of the Terraform state S3 bucket. Reference this from environments/phase0/backend.tf."
  value       = aws_s3_bucket.tf_state.id
}

output "lock_table" {
  description = "Name of the DynamoDB table used for Terraform state locking."
  value       = aws_dynamodb_table.tf_locks.name
}

output "ecr_backend_repo_url" {
  description = "URL of the backend container ECR repository. Consumed by phase0/main.tf via data source."
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_ingester_repo_urls" {
  description = "Map of ingester name to ECR repository URL."
  value       = { for k, v in aws_ecr_repository.ingesters : k => v.repository_url }
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider in IAM."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "ci_plan_role_arn" {
  description = "IAM role ARN that PR workflows assume (read-only + plan). Put this in GitHub repo secrets as AWS_PLAN_ROLE_ARN."
  value       = aws_iam_role.ci_plan.arn
}

output "ci_apply_role_arn" {
  description = "IAM role ARN that apply/destroy workflows assume (broad write). Put this in GitHub repo secrets as AWS_APPLY_ROLE_ARN."
  value       = aws_iam_role.ci_apply.arn
}

output "ci_image_push_role_arn" {
  description = "IAM role ARN that the app repo's backend-image workflow assumes (ECR push only)."
  value       = aws_iam_role.app_image_push.arn
}

output "secret_arns" {
  description = "Map of logical secret name to Secrets Manager ARN. Values are populated out-of-band; see README."
  value       = { for k, v in aws_secretsmanager_secret.app : k => v.arn }
}
