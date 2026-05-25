# frontend-static

S3 bucket configured for static website hosting with a public-read policy. No CloudFront, no domain, no TLS — see ADR 0002.

## Why no CloudFront?

- 15-20 min spin-up time per cycle vs. the rest of the stack at ~10-15 min total — would dominate `make up` latency.
- Adds a separate ACM cert (in `us-east-1`) and a hosted zone if we want a custom domain.
- The single client is the team, and the S3 website endpoint serves a SPA bundle just fine over HTTP for that audience.

Phase 1 adds CloudFront + ACM + a custom domain. The bucket created here will sit behind CloudFront with origin access — no schema change to the bucket.

## Bucket naming

S3 bucket names are globally unique. To survive rapid `make down` / `make up` cycles (S3 doesn't always release the name immediately), the bucket name carries a 6-hex random suffix: `companybrain-phase0-frontend-a3f9c2`. The current name is published to SSM at `/companybrain/phase0/s3/frontend_bucket` by the phase0 environment.

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `name_prefix` | Resource prefix | (required) |
| `index_document` | Index document | `index.html` |
| `error_document` | Error document (Vite SPAs typically point this at `index.html` for client-side routing) | `index.html` |

## Outputs

`bucket_name`, `bucket_arn`, `bucket_regional_domain_name`, `website_endpoint`, `website_url`.

## How the frontend gets deployed

The app repo's `frontend-build.yml` workflow builds the Vite bundle on push to `main` and uploads it as a GitHub Actions artifact. After `make up`, run:

```bash
make deploy-frontend     # in the TFE repo: downloads latest artifact, uploads to S3
```

Or just `aws s3 sync ./dist s3://<bucket-name>/ --delete` locally after `pnpm build`.
