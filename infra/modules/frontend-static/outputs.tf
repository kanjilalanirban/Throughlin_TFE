output "bucket_name" {
  description = "S3 bucket name."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "S3 bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional REST endpoint (used if you wire CloudFront in Phase 1)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "website_endpoint" {
  description = "S3 website hosting endpoint (no scheme). Phase 0 ships HTTP only."
  value       = aws_s3_bucket_website_configuration.this.website_endpoint
}

output "website_url" {
  description = "Full website URL (http://...). Open this in a browser after uploading the frontend bundle."
  value       = "http://${aws_s3_bucket_website_configuration.this.website_endpoint}"
}
