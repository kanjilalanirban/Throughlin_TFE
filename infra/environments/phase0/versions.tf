terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
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
      Lifecycle   = "ephemeral"
    }
  }
}
