data "aws_caller_identity" "current" {}

# GitHub-issued OIDC tokens use this fixed thumbprint set (rotates rarely).
# See https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name = "github-actions-oidc"
  }
}

# =============================================================================
# Plan role (TFE repo): read-only + state read/write for `terraform plan`.
# Assumed by any branch in the TFE repo, including PRs from forks if enabled.
# =============================================================================
resource "aws_iam_role" "ci_plan" {
  name = "companybrain-ci-plan"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo_tfe}:*"
        }
      }
    }]
  })

  tags = {
    Name = "companybrain-ci-plan"
  }
}

resource "aws_iam_role_policy_attachment" "ci_plan_readonly" {
  role       = aws_iam_role.ci_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Plan needs read+write on the state bucket and lock table.
resource "aws_iam_role_policy" "ci_plan_state_access" {
  name = "tf-state-rw"
  role = aws_iam_role.ci_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.tf_state.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.tf_state.arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.tf_locks.arn
      }
    ]
  })
}

# =============================================================================
# Apply role (TFE repo): broad write access for `terraform apply` and `destroy`.
# Restricted to the `main` branch and `workflow_dispatch` events on the TFE repo.
# =============================================================================
resource "aws_iam_role" "ci_apply" {
  name = "companybrain-ci-apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # Allow only main branch refs and workflow_dispatch from main.
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo_tfe}:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = {
    Name = "companybrain-ci-apply"
  }
}

# PowerUserAccess covers everything the ephemeral stack provisions (VPC, RDS,
# Fargate, Lambda, ALB, S3, Cognito, EventBridge, SSM, Secrets Manager values)
# without granting IAM admin. IAM resources for the ephemeral stack are created
# at bootstrap (the task/lambda execution roles), not by apply, so PowerUser is
# sufficient. Tighten later if scope grows.
resource "aws_iam_role_policy_attachment" "ci_apply_poweruser" {
  role       = aws_iam_role.ci_apply.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# Apply also needs IAM PassRole for the ECS task execution role, lambda
# execution roles, etc. that the ephemeral stack assigns to its resources.
resource "aws_iam_role_policy" "ci_apply_passrole" {
  name = "passrole-ephemeral-execution-roles"
  role = aws_iam_role.ci_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "iam:PassRole"
      Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/companybrain-phase0-*"
    }]
  })
}

# =============================================================================
# App-image push role (Throughlin_app repo): can only push images to ECR.
# Used by the backend-image build workflow in the app repo.
# =============================================================================
resource "aws_iam_role" "app_image_push" {
  name = "companybrain-app-image-push"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo_app}:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = {
    Name = "companybrain-app-image-push"
  }
}

resource "aws_iam_role_policy" "app_image_push" {
  name = "ecr-push"
  role = aws_iam_role.app_image_push.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage"
        ]
        Resource = concat(
          [aws_ecr_repository.backend.arn],
          [for r in aws_ecr_repository.ingesters : r.arn]
        )
      }
    ]
  })
}
