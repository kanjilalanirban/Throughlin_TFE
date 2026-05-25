terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  # Bootstrap uses LOCAL state on first apply because the S3 state bucket
  # does not yet exist. After the first successful apply, migrate to S3 with:
  #
  #   terraform init -migrate-state \
  #     -backend-config="bucket=companybrain-tf-state" \
  #     -backend-config="key=bootstrap/terraform.tfstate" \
  #     -backend-config="region=ca-central-1" \
  #     -backend-config="dynamodb_table=companybrain-tf-locks" \
  #     -backend-config="encrypt=true"
  #
  # See README.md for the full bootstrap procedure.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      App         = "mv01throu"
      Project     = "companybrain"
      Environment = "phase0"
      ManagedBy   = "terraform"
      CostCenter  = "phase0"
      Lifecycle   = "bootstrap"
    }
  }
}
