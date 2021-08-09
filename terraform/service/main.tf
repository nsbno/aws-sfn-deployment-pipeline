terraform {
  required_version = "1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.53.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "2.2.0"
    }
  }
  backend "s3" {
    key            = "<project-name>/main.tfstate"
    bucket         = "<service-account-id>-<terraform-state-bucket-suffix>"
    dynamodb_table = "<service-account-id>-<terraform-lock-table-suffix>"
    region         = "eu-west-1"
  }
}

provider "aws" {
  region              = "eu-west-1"
  allowed_account_ids = ["<service-account-id>"]
}

data "aws_caller_identity" "this" {}
data "aws_region" "this" {}
data "aws_availability_zones" "this" {}

locals {
  current_account_id = data.aws_caller_identity.this.account_id
  current_region     = data.aws_region.this.name
  name_prefix        = "<project-name>"
  tags = {
    terraform   = "true"
    environment = "service"
    application = local.name_prefix
  }
  service_account_id = "<service-account-id>"
  test_account_id    = "<test-account-id>"
  stage_account_id   = "<stage-account-id>"
  prod_account_id    = "<prod-account-id>"
  trusted_accounts = [
    local.current_account_id,
    local.test_account_id,
    local.stage_account_id,
    local.prod_account_id,
  ]
  vpc_cidr_block = "192.168.50.0/24"
  public_cidr_blocks = [for k, v in data.aws_availability_zones.this.names :
  cidrsubnet(local.vpc_cidr_block, 4, k)]
  state_machine_arns = [aws_sfn_state_machine.main.arn]
}


###############################################
#                                             #
# VPC                                         #
# ---                                         #
# Mainly used for ad-hoc Fargate tasks        #
#                                             #
###############################################
module "vpc" {
  source               = "github.com/nsbno/terraform-aws-vpc?ref=ec7f57f"
  name_prefix          = local.name_prefix
  cidr_block           = local.vpc_cidr_block
  availability_zones   = data.aws_availability_zones.this.names
  public_subnet_cidrs  = local.public_cidr_blocks
  create_nat_gateways  = false
  enable_dns_hostnames = true
  tags                 = local.tags
}


##################################
#                                #
# Artifact bucket                #
#                                #
##################################
resource "aws_s3_bucket" "artifacts" {
  bucket = "${local.current_account_id}-${local.name_prefix}-pipeline-artifact"
  acl    = "private"
  versioning {
    enabled = true
  }
  tags = local.tags
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket            = aws_s3_bucket.artifacts.id
  block_public_acls = true
}

# Allow trusted accounts to access the project bucket
resource "aws_s3_bucket_policy" "s3_to_accounts" {
  bucket = aws_s3_bucket.artifacts.id
  policy = data.aws_iam_policy_document.s3_for_accounts.json
}


###############################################
#                                             #
# CI user                                     #
# ---                                         #
# IAM user with limited access to artifact    #
# stores such as S3 and ECR                   #
#                                             #
###############################################
module "ci_machine_user" {
  source      = "github.com/nsbno/terraform-aws-circleci-repository-user?ref=d9fb611"
  name_prefix = local.name_prefix
  allowed_s3_write_arns = [
    aws_s3_bucket.artifacts.arn
  ]
  allowed_s3_read_arns = [
    # ARNs of S3 buckets that the CI can read from
  ]
  allowed_ecr_arns = [
    # ARNs of ECR repositories that the CI can authenticate
    # against and push to
  ]
  ci_parameters_key = aws_kms_alias.ci.id
}

resource "aws_kms_key" "ci" {
  description = "KMS key for encrypting parameters shared with CircleCI."
}

resource "aws_kms_alias" "ci" {
  name          = "alias/${local.name_prefix}-ci-parameters"
  target_key_id = aws_kms_key.ci.id
}


###############################################
#                                             #
# set-version                                 #
# ---                                         #
# Lambda function that updates SSM parameters #
# to reference latest application versions    #
#                                             #
###############################################
module "set_version" {
  source      = "github.com/nsbno/terraform-aws-pipeline-set-version?ref=ee68497"
  name_prefix = local.name_prefix
  tags        = local.tags
}

resource "aws_iam_role_policy" "role_assume_to_set_version" {
  role   = module.set_version.lambda_exec_role_id
  policy = data.aws_iam_policy_document.role_assume_for_set_version.json
}


###############################################
#                                             #
# single-use-fargate-task                     #
# ---                                         #
# Lambda function that can be used to spin up #
# ad-hoc Fargate tasks                        #
#                                             #
###############################################
module "single_use_fargate_task" {
  source      = "github.com/nsbno/terraform-aws-single-use-fargate-task?ref=749146a"
  name_prefix = local.name_prefix
  tags        = local.tags
}

resource "aws_iam_role_policy" "pass_role_to_single_use_fargate_task" {
  policy = data.aws_iam_policy_document.pass_role_for_single_use_fargate_task.json
  role   = module.single_use_fargate_task.lambda_exec_role_id
}

resource "aws_iam_role" "fargate_task" {
  name               = "${local.name_prefix}-single-use-tasks"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "role_assume_to_fargate_task" {
  policy = data.aws_iam_policy_document.role_assume_for_fargate_task.json
  role   = aws_iam_role.fargate_task.id
}

resource "aws_iam_role_policy" "logs_to_fargate_task" {
  policy = data.aws_iam_policy_document.logs_for_fargate_task.json
  role   = aws_iam_role.fargate_task.id
}

resource "aws_iam_role_policy" "s3_to_fargate_task" {
  policy = data.aws_iam_policy_document.s3_for_fargate_task.json
  role   = aws_iam_role.fargate_task.id
}

resource "aws_iam_role_policy" "task_status_to_fargate_task" {
  policy = data.aws_iam_policy_document.task_status_for_fargate_task.json
  role   = aws_iam_role.fargate_task.id
}

resource "aws_iam_role_policy" "metrics_to_fargate_task" {
  policy = data.aws_iam_policy_document.metrics_for_fargate_task.json
  role   = aws_iam_role.fargate_task.id
}

resource "aws_iam_role" "deployment" {
  name               = "${local.name_prefix}-trusted-deployment"
  assume_role_policy = data.aws_iam_policy_document.trusted_account_deployment_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "admin_to_deployment" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.deployment.id
}


###############################################
#                                             #
# trigger-pipeline                            #
# ---                                         #
# Lambda function that starts a Step          #
# Functions execution on file upload to S3    #
#                                             #
###############################################
module "trigger_pipeline" {
  source               = "github.com/nsbno/terraform-aws-trigger-pipeline?ref=283d140"
  name_prefix          = local.name_prefix
  artifact_bucket_name = aws_s3_bucket.artifacts.id
  state_machine_arns   = local.state_machine_arns
  tags                 = local.tags
}


###############################################
#                                             #
# error-catcher                               #
# ---                                         #
# Lambda function that stops a Step Functions #
# execution if there are any errors           #
#                                             #
###############################################
module "error_catcher" {
  source             = "github.com/nsbno/terraform-aws-pipeline-error-catcher?ref=3f74981"
  state_machine_arns = local.state_machine_arns
  name_prefix        = local.name_prefix
  tags               = local.tags
}


###############################################
#                                             #
# Delivery pipelines                          #
# ---                                         #
# Delivery pipelines implemented as AWS Step  #
# Functions state machines                    #
#                                             #
###############################################
resource "aws_iam_role" "sfn" {
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "lambda_to_sfn" {
  policy = data.aws_iam_policy_document.lambda_for_sfn.json
  role   = aws_iam_role.sfn.id
}

# Use our JSON state machine template and dynamically fill in
# the required fields for our deployment pipeline
resource "aws_sfn_state_machine" "main" {
  name = "${local.name_prefix}-delivery-pipeline"
  definition = templatefile("./sfn-template-full.json.tpl", {
    error_catcher = {
      function_name = module.error_catcher.function_name
    }
    set_version = {
      function_name = module.set_version.function_name
      payloads = {
        initial = jsonencode(local.sfn_common_set_version_payloads.initial)
        service = jsonencode(local.sfn_common_set_version_payloads.service)
        test    = jsonencode(local.sfn_common_set_version_payloads.test)
        stage   = jsonencode(local.sfn_common_set_version_payloads.stage)
        prod    = jsonencode(local.sfn_common_set_version_payloads.prod)
      }
    }
    fargate_task = {
      function_name = module.single_use_fargate_task.function_name
      payloads = {
        service = jsonencode(local.sfn_common_fargate_payloads.service)
        test    = jsonencode(local.sfn_common_fargate_payloads.test)
        stage   = jsonencode(local.sfn_common_fargate_payloads.stage)
        prod    = jsonencode(local.sfn_common_fargate_payloads.prod)
      }
    }
  })
  role_arn = aws_iam_role.sfn.arn
  tags     = local.tags
}

# TODO Uncomment and add one per docker container
/*
module "<ecr-container-name>" {
  source      = "github.com/nsbno/terraform-aws-ecr?ref=c25010b"
  name_prefix = "${local.name_prefix}-<container-name>"
  trusted_accounts = local.trusted_accounts
}*/
