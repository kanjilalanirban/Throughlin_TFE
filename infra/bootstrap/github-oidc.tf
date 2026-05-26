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
        # Apply/destroy workflows declare `environment: phase0`, which makes
        # GitHub's OIDC subject claim `environment:phase0` instead of
        # `ref:refs/heads/main`. The Environment is the protection boundary
        # (configurable reviewers in GitHub UI); allowing it here is the
        # correct narrowing. Also accept main branch refs for safety in case
        # we ever remove the environment requirement.
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.github_org}/${var.github_repo_tfe}:environment:phase0",
            "repo:${var.github_org}/${var.github_repo_tfe}:ref:refs/heads/main",
          ]
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
# without granting IAM admin.
resource "aws_iam_role_policy_attachment" "ci_apply_poweruser" {
  role       = aws_iam_role.ci_apply.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# The ephemeral stack creates its own task/lambda execution roles inside the
# fargate-service and lambda-ingester modules (not in bootstrap). The apply
# role needs IAM CRUD on those roles, plus PassRole to attach them. All
# scoped to `companybrain-phase0-*` so the apply role cannot touch bootstrap
# IAM resources (which carry the `companybrain-ci-*` / `companybrain-app-*`
# naming prefix).
resource "aws_iam_role_policy" "ci_apply_iam_for_ephemeral" {
  name = "manage-ephemeral-iam-roles"
  role = aws_iam_role.ci_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageEphemeralRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:UpdateRole",
          "iam:UpdateRoleDescription",
          "iam:UpdateAssumeRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:ListRoleTags",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:PassRole",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/companybrain-phase0-*"
      },
      {
        # The aws_iam_role_policy_attachment resource needs to look up which
        # AWS-managed policies are attached; that requires GetPolicy + GetPolicyVersion
        # against the managed policy ARNs we attach (AmazonECSTaskExecutionRolePolicy,
        # AWSLambdaBasicExecutionRole, AWSLambdaVPCAccessExecutionRole).
        Sid    = "ReadManagedPoliciesAttachedToEphemeralRoles"
        Effect = "Allow"
        Action = [
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
        ]
        Resource = "arn:aws:iam::aws:policy/*"
      },
    ]
  })
}

# =============================================================================
# App deploy role (Throughlin_app repo): used by backend-image and
# frontend-deploy workflows. Permissions:
#   - ECR: push backend + ingester images
#   - SSM: read /companybrain/phase0/* (frontend reads ALB URL + bucket name)
#   - S3:  write to companybrain-phase0-frontend-* (uploads bundle)
#   - ECS: force redeploy of the api service after backend image push
# Name kept as `companybrain-app-image-push` to avoid destroy+create churn on
# the IAM role (and the GH secret pointing at it). Phase 1 may rename.
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
  name = "app-deploy"
  role = aws_iam_role.app_image_push.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EcrAuth"
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPushBackendAndIngesters"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage",
        ]
        Resource = concat(
          [aws_ecr_repository.backend.arn],
          [for r in aws_ecr_repository.ingesters : r.arn],
        )
      },
      {
        Sid    = "ReadSsmParametersForDeploy"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
        ]
        Resource = "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/companybrain/phase0/*"
      },
      {
        Sid    = "ListFrontendBucket"
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::companybrain-phase0-frontend-*"
      },
      {
        Sid    = "WriteToFrontendBucket"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObject",
        ]
        Resource = "arn:aws:s3:::companybrain-phase0-frontend-*/*"
      },
      {
        Sid    = "ForceEcsRedeployAfterImagePush"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:UpdateService",
        ]
        Resource = "arn:aws:ecs:*:${data.aws_caller_identity.current.account_id}:service/companybrain-phase0-cluster/companybrain-phase0-*"
      },
    ]
  })
}
