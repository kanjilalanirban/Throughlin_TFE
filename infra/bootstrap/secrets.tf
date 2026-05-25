locals {
  # Logical name -> human description of what the secret holds.
  # We deliberately create the containers but NOT the values. Populate
  # values out-of-band via the AWS console or:
  #
  #   aws secretsmanager put-secret-value \
  #     --secret-id companybrain/phase0/anthropic/api-key \
  #     --secret-string '<the-actual-key>'
  #
  # This keeps secret values out of Terraform state.
  app_secrets = {
    "anthropic/api-key" = "Anthropic API key for Claude calls."
    "jira/oauth-client" = "Jira OAuth 2.0 (3LO) client_id + client_secret + refresh_token (JSON)."
    "github/app-key"    = "GitHub App private key (PEM) + app_id + installation_id (JSON)."
  }
}

resource "aws_secretsmanager_secret" "app" {
  for_each = local.app_secrets

  name        = "companybrain/phase0/${each.key}"
  description = each.value

  # 7-day recovery window in case of accidental delete; minimum is 7.
  recovery_window_in_days = 7

  tags = {
    Name = "companybrain-phase0-${replace(each.key, "/", "-")}"
  }
}

# Note: RDS master user password is NOT bootstrapped. The ephemeral
# rds-postgres module sets `manage_master_user_password = true`, so RDS
# generates a fresh password into a new secret on every `make up` and
# cleans it up on `make down`. App reads it via the SSM parameter
# `/companybrain/phase0/rds/secret_arn` published by the phase0 env.
