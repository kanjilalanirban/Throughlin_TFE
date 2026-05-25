output "api_url" {
  description = "Backend API URL (HTTP only in Phase 0)."
  value       = "http://${module.fargate.alb_dns_name}"
}

output "frontend_url" {
  description = "Frontend website URL."
  value       = module.frontend.website_url
}

output "frontend_bucket" {
  description = "Frontend S3 bucket name (for `aws s3 sync` deploys)."
  value       = module.frontend.bucket_name
}

output "rds_endpoint" {
  description = "RDS Postgres endpoint."
  value       = module.rds.endpoint
}

output "rds_secret_arn" {
  description = "Secrets Manager ARN holding the RDS master credentials (managed by RDS, recreated each session)."
  value       = module.rds.master_user_secret_arn
  sensitive   = true
}

output "raw_bucket" {
  description = "S3 raw-data bucket (per-stack name)."
  value       = aws_s3_bucket.raw.id
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID."
  value       = aws_cognito_user_pool.this.id
}

output "cognito_client_id" {
  description = "Cognito web client ID."
  value       = aws_cognito_user_pool_client.web.id
}

output "ecs_cluster" {
  description = "ECS cluster name."
  value       = module.fargate.cluster_name
}

output "ecs_service" {
  description = "ECS service name."
  value       = module.fargate.service_name
}

output "ingester_function_names" {
  description = "Map of ingester name to Lambda function name. Value is \"(disabled - no image)\" when the ingester is not enabled (no image tag set in ingester_image_tags)."
  value = {
    jira       = length(module.ingester_jira) > 0 ? module.ingester_jira[0].function_name : "(disabled - no image)"
    github     = length(module.ingester_github) > 0 ? module.ingester_github[0].function_name : "(disabled - no image)"
    hris       = length(module.ingester_hris) > 0 ? module.ingester_hris[0].function_name : "(disabled - no image)"
    normalizer = length(module.normalizer) > 0 ? module.normalizer[0].function_name : "(disabled - no image)"
  }
}
