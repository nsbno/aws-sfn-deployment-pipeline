terraform {
  required_version = "0.12.29"

  backend "s3" {
    key            = "<project-name>/main.tfstate"
    bucket         = "<test-account-id>-<terraform-state-bucket-suffix>"
    dynamodb_table = "<test-account-id>-<terraform-lock-table-suffix>"
    region         = "eu-west-1"
  }
}

provider "aws" {
  version             = "3.3.0"
  region              = "eu-west-1"
  allowed_account_ids = ["<test-account-id>"]
}

locals {
  name_prefix = "<project-name>"
}

module "<project-name>" {
  source      = "../modules/template"
  name_prefix = local.name_prefix
  tags = {
    terraform   = "true"
    environment = "test"
    application = local.name_prefix
  }
}

