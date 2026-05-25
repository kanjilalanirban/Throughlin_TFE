output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.this.name
}

output "task_role_arn" {
  description = "Task IAM role ARN (used by the running app)."
  value       = aws_iam_role.task.arn
}

output "alb_arn" {
  description = "ALB ARN."
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "ALB DNS name. This is the public endpoint of the API in Phase 0 (no custom domain)."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "ALB Route 53 hosted zone ID (kept for Phase 1 when we add a domain alias record)."
  value       = aws_lb.this.zone_id
}

output "log_group_name" {
  description = "CloudWatch log group name for the task logs."
  value       = aws_cloudwatch_log_group.tasks.name
}
