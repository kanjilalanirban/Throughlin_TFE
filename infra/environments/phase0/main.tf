data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Read from bootstrap (always-on)
# -----------------------------------------------------------------------------
data "aws_ecr_repository" "backend" {
  name = "companybrain-backend"
}

data "aws_ecr_repository" "ingesters" {
  for_each = toset(["jira-ingester", "github-ingester", "hris-ingester", "normalizer"])
  name     = "companybrain-${each.key}"
}

data "aws_secretsmanager_secret" "anthropic" {
  name = "companybrain/phase0/anthropic/api-key"
}

data "aws_secretsmanager_secret" "jira_oauth" {
  name = "companybrain/phase0/jira/oauth-client"
}

data "aws_secretsmanager_secret" "github_app" {
  name = "companybrain/phase0/github/app-key"
}

locals {
  bootstrap_secret_arns = [
    data.aws_secretsmanager_secret.anthropic.arn,
    data.aws_secretsmanager_secret.jira_oauth.arn,
    data.aws_secretsmanager_secret.github_app.arn,
  ]

  # Resolved image URIs.
  # backend_image: empty string means the module uses its nginx placeholder.
  # Fargate doesn't validate the URI at task-def creation, so passing a real
  # ECR URI before an image exists is "safe" but leaves the task unhealthy.
  # We gate it on backend_image_exists so the default state is a known-good
  # placeholder rather than a perpetually-restarting Fargate task.
  backend_image = var.backend_image_exists ? "${data.aws_ecr_repository.backend.repository_url}:${var.backend_image_tag}" : ""

  # ingester_image_uris: only computed for ingesters that have a real tag
  # configured. AWS Lambda validates that the image exists in YOUR private
  # ECR at function creation time — there is no Lambda equivalent of
  # "deploy first, push image later". We therefore SKIP module creation
  # entirely when no tag is set (see `ingester_enabled` below).
  ingester_image_uris = {
    jira       = "${data.aws_ecr_repository.ingesters["jira-ingester"].repository_url}:${var.ingester_image_tags["jira"]}"
    github     = "${data.aws_ecr_repository.ingesters["github-ingester"].repository_url}:${var.ingester_image_tags["github"]}"
    hris       = "${data.aws_ecr_repository.ingesters["hris-ingester"].repository_url}:${var.ingester_image_tags["hris"]}"
    normalizer = "${data.aws_ecr_repository.ingesters["normalizer"].repository_url}:${var.ingester_image_tags["normalizer"]}"
  }

  # Per-ingester gate: true once an image has been pushed and the tag is set.
  ingester_enabled = {
    jira       = var.ingester_image_tags["jira"] != ""
    github     = var.ingester_image_tags["github"] != ""
    hris       = var.ingester_image_tags["hris"] != ""
    normalizer = var.ingester_image_tags["normalizer"] != ""
  }
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
module "vpc" {
  source      = "../../modules/vpc"
  name_prefix = var.name_prefix
}

# -----------------------------------------------------------------------------
# RDS
# -----------------------------------------------------------------------------
module "rds" {
  source = "../../modules/rds-postgres"

  name_prefix       = var.name_prefix
  subnet_ids        = module.vpc.private_subnet_ids
  security_group_id = module.vpc.rds_security_group_id
}

# -----------------------------------------------------------------------------
# Cognito (minimal Phase 0 user pool)
# -----------------------------------------------------------------------------
resource "aws_cognito_user_pool" "this" {
  name = "${var.name_prefix}-users"

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  mfa_configuration = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  auto_verified_attributes = ["email"]

  tags = {
    Name = "${var.name_prefix}-users"
  }
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.name_prefix}-web"
  user_pool_id = aws_cognito_user_pool.this.id

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  generate_secret               = false
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true
  access_token_validity         = 60
  id_token_validity             = 60
  refresh_token_validity        = 30
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

# -----------------------------------------------------------------------------
# S3 raw-data bucket (per-stack random suffix)
# -----------------------------------------------------------------------------
resource "random_id" "raw_suffix" {
  byte_length = 3
}

resource "aws_s3_bucket" "raw" {
  bucket        = "${var.name_prefix}-raw-${random_id.raw_suffix.hex}"
  force_destroy = true

  tags = {
    Name = "${var.name_prefix}-raw-${random_id.raw_suffix.hex}"
  }
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket = aws_s3_bucket.raw.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id

  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------------------------------------------------------
# Fargate (backend API)
# -----------------------------------------------------------------------------
module "fargate" {
  source = "../../modules/fargate-service"

  name_prefix               = var.name_prefix
  vpc_id                    = module.vpc.vpc_id
  public_subnet_ids         = module.vpc.public_subnet_ids
  private_subnet_ids        = module.vpc.private_subnet_ids
  alb_security_group_id     = module.vpc.alb_security_group_id
  fargate_security_group_id = module.vpc.fargate_security_group_id

  container_image = local.backend_image

  secret_arns_to_read = concat(
    local.bootstrap_secret_arns,
    [module.rds.master_user_secret_arn]
  )

  ssm_parameter_arns_to_read = [
    "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/companybrain/phase0/*"
  ]
}

# -----------------------------------------------------------------------------
# Lambda ingesters
# -----------------------------------------------------------------------------
module "ingester_jira" {
  count  = local.ingester_enabled["jira"] ? 1 : 0
  source = "../../modules/lambda-ingester"

  name_prefix         = var.name_prefix
  ingester_name       = "jira"
  image_uri           = local.ingester_image_uris["jira"]
  schedule_expression = var.jira_schedule
  subnet_ids          = module.vpc.private_subnet_ids
  security_group_id   = module.vpc.lambda_security_group_id
  raw_bucket_arn      = aws_s3_bucket.raw.arn

  secret_arns_to_read = [
    data.aws_secretsmanager_secret.jira_oauth.arn,
    module.rds.master_user_secret_arn,
  ]

  environment_variables = {
    RAW_BUCKET = aws_s3_bucket.raw.id
  }
}

module "ingester_github" {
  count  = local.ingester_enabled["github"] ? 1 : 0
  source = "../../modules/lambda-ingester"

  name_prefix         = var.name_prefix
  ingester_name       = "github"
  image_uri           = local.ingester_image_uris["github"]
  schedule_expression = var.github_schedule
  subnet_ids          = module.vpc.private_subnet_ids
  security_group_id   = module.vpc.lambda_security_group_id
  raw_bucket_arn      = aws_s3_bucket.raw.arn

  secret_arns_to_read = [
    data.aws_secretsmanager_secret.github_app.arn,
    module.rds.master_user_secret_arn,
  ]

  environment_variables = {
    RAW_BUCKET = aws_s3_bucket.raw.id
  }
}

module "ingester_hris" {
  count  = local.ingester_enabled["hris"] ? 1 : 0
  source = "../../modules/lambda-ingester"

  name_prefix         = var.name_prefix
  ingester_name       = "hris"
  image_uri           = local.ingester_image_uris["hris"]
  schedule_expression = var.hris_schedule
  subnet_ids          = module.vpc.private_subnet_ids
  security_group_id   = module.vpc.lambda_security_group_id
  raw_bucket_arn      = aws_s3_bucket.raw.arn

  secret_arns_to_read = [
    module.rds.master_user_secret_arn,
  ]

  environment_variables = {
    RAW_BUCKET = aws_s3_bucket.raw.id
  }
}

module "normalizer" {
  count  = local.ingester_enabled["normalizer"] ? 1 : 0
  source = "../../modules/lambda-ingester"

  name_prefix         = var.name_prefix
  ingester_name       = "normalizer"
  image_uri           = local.ingester_image_uris["normalizer"]
  schedule_expression = "" # triggered by S3 events, not a schedule
  subnet_ids          = module.vpc.private_subnet_ids
  security_group_id   = module.vpc.lambda_security_group_id
  raw_bucket_arn      = aws_s3_bucket.raw.arn

  secret_arns_to_read = [
    module.rds.master_user_secret_arn,
  ]

  environment_variables = {
    RAW_BUCKET = aws_s3_bucket.raw.id
  }
}

# S3 -> normalizer Lambda trigger (only wired when normalizer exists)
resource "aws_lambda_permission" "normalizer_s3" {
  count = local.ingester_enabled["normalizer"] ? 1 : 0

  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = module.normalizer[0].function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw.arn
}

resource "aws_s3_bucket_notification" "raw" {
  count = local.ingester_enabled["normalizer"] ? 1 : 0

  bucket = aws_s3_bucket.raw.id

  lambda_function {
    lambda_function_arn = module.normalizer[0].function_arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.normalizer_s3]
}

# -----------------------------------------------------------------------------
# Frontend
# -----------------------------------------------------------------------------
module "frontend" {
  source      = "../../modules/frontend-static"
  name_prefix = var.name_prefix
}

# -----------------------------------------------------------------------------
# Published outputs (SSM Parameter Store) — the cross-repo contract
# -----------------------------------------------------------------------------
locals {
  ssm_params = {
    "/companybrain/phase0/region"     = data.aws_region.current.name
    "/companybrain/phase0/account_id" = data.aws_caller_identity.current.account_id

    "/companybrain/phase0/rds/endpoint"      = module.rds.endpoint
    "/companybrain/phase0/rds/address"       = module.rds.address
    "/companybrain/phase0/rds/port"          = tostring(module.rds.port)
    "/companybrain/phase0/rds/database_name" = module.rds.database_name
    "/companybrain/phase0/rds/secret_arn"    = module.rds.master_user_secret_arn

    "/companybrain/phase0/alb/dns_name" = module.fargate.alb_dns_name
    "/companybrain/phase0/alb/url"      = "http://${module.fargate.alb_dns_name}"

    "/companybrain/phase0/cognito/user_pool_id" = aws_cognito_user_pool.this.id
    "/companybrain/phase0/cognito/client_id"    = aws_cognito_user_pool_client.web.id

    "/companybrain/phase0/ecr/backend_uri" = data.aws_ecr_repository.backend.repository_url

    "/companybrain/phase0/s3/raw_bucket"      = aws_s3_bucket.raw.id
    "/companybrain/phase0/s3/frontend_bucket" = module.frontend.bucket_name
    "/companybrain/phase0/s3/frontend_url"    = module.frontend.website_url

    "/companybrain/phase0/secrets/anthropic_arn" = data.aws_secretsmanager_secret.anthropic.arn
    "/companybrain/phase0/secrets/jira_arn"      = data.aws_secretsmanager_secret.jira_oauth.arn
    "/companybrain/phase0/secrets/github_arn"    = data.aws_secretsmanager_secret.github_app.arn
  }
}

resource "aws_ssm_parameter" "published" {
  for_each = local.ssm_params

  name  = each.key
  type  = "String"
  value = each.value

  tags = {
    Name = each.key
  }
}
