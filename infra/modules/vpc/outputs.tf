output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (host ALB and NAT GW)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (host Fargate, Lambda, RDS)."
  value       = aws_subnet.private[*].id
}

output "alb_security_group_id" {
  description = "Security group ID for the ALB."
  value       = aws_security_group.alb.id
}

output "fargate_security_group_id" {
  description = "Security group ID for Fargate tasks."
  value       = aws_security_group.fargate.id
}

output "rds_security_group_id" {
  description = "Security group ID for RDS."
  value       = aws_security_group.rds.id
}

output "lambda_security_group_id" {
  description = "Security group ID for VPC-attached Lambdas."
  value       = aws_security_group.lambda.id
}
