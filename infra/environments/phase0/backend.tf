terraform {
  backend "s3" {
    bucket         = "companybrain-tf-state"
    key            = "phase0/terraform.tfstate"
    region         = "ca-central-1"
    dynamodb_table = "companybrain-tf-locks"
    encrypt        = true
  }
}
