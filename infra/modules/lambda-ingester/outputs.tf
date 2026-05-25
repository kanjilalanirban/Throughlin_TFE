output "function_name" {
  description = "Lambda function name."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "Lambda function ARN."
  value       = aws_lambda_function.this.arn
}

output "role_arn" {
  description = "Execution role ARN (useful when wiring S3 notifications: the role needs s3:GetObject for S3-triggered invocations)."
  value       = aws_iam_role.this.arn
}

output "log_group_name" {
  description = "CloudWatch log group for the function."
  value       = aws_cloudwatch_log_group.this.name
}
