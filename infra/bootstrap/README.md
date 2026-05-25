# Bootstrap

**Always-on resources. Created once, by hand. Never destroyed by `make down`.**

This layer provisions the floor that the ephemeral stack depends on:

- S3 bucket for Terraform state + DynamoDB lock table
- GitHub OIDC provider + IAM roles for CI (plan, apply, app-image-push)
- ECR repositories for the backend container and each ingester
- Secrets Manager containers for Anthropic / Jira / GitHub App credentials (values populated out-of-band)

## First-time bootstrap procedure

1. **Authenticate to AWS as a privileged human** (root for first-ever run; thereafter via IAM Identity Center with admin permission set):
   ```bash
   aws sso login --profile companybrain-admin
   export AWS_PROFILE=companybrain-admin
   ```

2. **Initialize with local state** (the S3 state bucket does not yet exist):
   ```bash
   cd infra/bootstrap
   terraform init
   ```

3. **Apply**:
   ```bash
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

4. **Capture outputs** — you will need them:
   ```bash
   terraform output
   ```
   Save:
   - `state_bucket` and `lock_table` → into `environments/phase0/backend.tf`
   - `ci_plan_role_arn` → add to **this** repo's GitHub Secrets as `AWS_PLAN_ROLE_ARN`
   - `ci_apply_role_arn` → add to **this** repo's GitHub Secrets as `AWS_APPLY_ROLE_ARN`
   - `ci_image_push_role_arn` → add to the **app** repo's (Throughlin_app) GitHub Secrets as `AWS_IMAGE_PUSH_ROLE_ARN`

5. **Migrate bootstrap state to S3** (so future bootstrap edits are stored alongside the rest):
   ```bash
   terraform init -migrate-state \
     -backend-config="bucket=companybrain-tf-state" \
     -backend-config="key=bootstrap/terraform.tfstate" \
     -backend-config="region=ca-central-1" \
     -backend-config="dynamodb_table=companybrain-tf-locks" \
     -backend-config="encrypt=true"
   ```
   When prompted, answer `yes` to copy the existing state to the new backend.

6. **Delete the local state file** (it is now in S3):
   ```bash
   rm -f terraform.tfstate terraform.tfstate.backup
   ```

7. **Populate secret values** for the empty containers:
   ```bash
   aws secretsmanager put-secret-value \
     --secret-id companybrain/phase0/anthropic/api-key \
     --secret-string 'sk-ant-...'

   aws secretsmanager put-secret-value \
     --secret-id companybrain/phase0/jira/oauth-client \
     --secret-string '{"client_id":"...","client_secret":"...","refresh_token":"..."}'

   aws secretsmanager put-secret-value \
     --secret-id companybrain/phase0/github/app-key \
     --secret-string '{"app_id":"...","installation_id":"...","private_key":"-----BEGIN..."}'
   ```

8. **Activate the `App` cost-allocation tag** in the AWS Billing console (Billing → Cost allocation tags → User-defined → activate `App`). Takes ~24h to appear in Cost Explorer.

9. **Activate Cost Anomaly Detection** and set up the $50/$100/$200 billing alarms.

## Subsequent edits

After step 5, normal Terraform flow works:

```bash
cd infra/bootstrap
terraform init      # backend already configured
terraform plan
terraform apply
```

## What's intentionally NOT here

- App container images — those are built and pushed by the app repo's CI to the ECR repos created above.
- RDS, Fargate, VPC, etc. — those are ephemeral; they live in `infra/environments/phase0/`.
- Anything that should be re-created on every `make up`.

## Destroying bootstrap

**Don't.** The state bucket and lock table have `prevent_destroy = true`. Tearing them down would orphan the ephemeral stack's state and corrupt the OIDC trust relationships in IAM. If you genuinely need to destroy the project, do it in this order:

1. `make down` in `environments/phase0/` (destroy ephemeral first)
2. Manually empty + delete the ECR repos (Terraform won't delete non-empty repos)
3. Manually empty + delete the secrets via `aws secretsmanager delete-secret --force-delete-without-recovery`
4. Remove `prevent_destroy` blocks
5. `terraform destroy` here

Then the AWS account itself can be retired or repurposed.
