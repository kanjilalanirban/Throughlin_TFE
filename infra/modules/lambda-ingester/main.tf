data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  function_name = "${var.name_prefix}-${var.ingester_name}"

  # Placeholder image: AWS Lambda's official base; the function will fail
  # gracefully (no handler found) until a real image is pushed.
  effective_image = var.image_uri != "" ? var.image_uri : "public.ecr.aws/lambda/python:3.12"
}

# -----------------------------------------------------------------------------
# CloudWatch log group
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "/aws/lambda/${local.function_name}"
  }
}

# -----------------------------------------------------------------------------
# IAM
# -----------------------------------------------------------------------------
resource "aws_iam_role" "this" {
  name = "${local.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${local.function_name}-role"
  }
}

# Basic logging.
resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# VPC ENI management.
resource "aws_iam_role_policy_attachment" "vpc" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# S3 raw-bucket write + read.
resource "aws_iam_role_policy" "s3_raw" {
  name = "raw-bucket-rw"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [var.raw_bucket_arn, "${var.raw_bucket_arn}/*"]
      }
    ]
  })
}

# Secrets + SSM read (when configured).
resource "aws_iam_role_policy" "reads" {
  count = length(var.secret_arns_to_read) + length(var.ssm_parameter_arns_to_read) > 0 ? 1 : 0

  name = "runtime-reads"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      length(var.secret_arns_to_read) > 0 ? [{
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.secret_arns_to_read
      }] : [],
      length(var.ssm_parameter_arns_to_read) > 0 ? [{
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = var.ssm_parameter_arns_to_read
      }] : []
    )
  })
}

# -----------------------------------------------------------------------------
# Lambda function (container-image based)
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "this" {
  function_name = local.function_name
  role          = aws_iam_role.this.arn

  package_type = "Image"
  image_uri    = local.effective_image

  memory_size = var.memory_mb
  timeout     = var.timeout_seconds

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  environment {
    variables = merge(
      {
        ENVIRONMENT         = "phase0"
        AWS_REGION_OVERRIDE = data.aws_region.current.name
      },
      var.environment_variables
    )
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.this.name
  }

  tags = {
    Name = local.function_name
  }

  depends_on = [
    aws_cloudwatch_log_group.this,
    aws_iam_role_policy_attachment.logs,
    aws_iam_role_policy_attachment.vpc
  ]
}

# -----------------------------------------------------------------------------
# EventBridge schedule (optional)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "schedule" {
  count = var.schedule_expression != "" ? 1 : 0

  name                = "${local.function_name}-schedule"
  description         = "Schedule for ${local.function_name}"
  schedule_expression = var.schedule_expression

  tags = {
    Name = "${local.function_name}-schedule"
  }
}

resource "aws_cloudwatch_event_target" "schedule" {
  count = var.schedule_expression != "" ? 1 : 0

  rule      = aws_cloudwatch_event_rule.schedule[0].name
  target_id = "lambda"
  arn       = aws_lambda_function.this.arn
}

resource "aws_lambda_permission" "schedule" {
  count = var.schedule_expression != "" ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule[0].arn
}
