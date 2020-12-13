terraform {
  required_version = "0.12.29"

  backend "s3" {
    key            = "<project-name>/main.tfstate"
    bucket         = "<service-account-id>-<terraform-state-bucket-suffix>"
    dynamodb_table = "<service-account-id>-<terraform-lock-table-suffix>"
    region         = "eu-west-1"
  }
}

provider "archive" {
  version = "~> 1.3"
}

provider "aws" {
  version             = "3.3.0"
  region              = "eu-west-1"
  allowed_account_ids = ["<service-account-id>"]
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "main" {}

locals {
  current_account_id = data.aws_caller_identity.current.account_id
  current_region     = data.aws_region.current.name
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
  public_cidr_blocks = [for k, v in data.aws_availability_zones.main.names :
  cidrsubnet(local.vpc_cidr_block, 4, k)]
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
  availability_zones   = data.aws_availability_zones.main.names
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
resource "aws_s3_bucket" "project_bucket" {
  bucket = "${local.current_account_id}-${local.name_prefix}-pipeline-artifact"
  acl    = "private"
  versioning {
    enabled = true
  }
  tags = local.tags
}

# Allow trusted accounts to access the project bucket
resource "aws_s3_bucket_policy" "s3_to_accounts" {
  bucket = aws_s3_bucket.project_bucket.id
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
    aws_s3_bucket.project_bucket.arn
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


##################################
#                                #
# Step Function                  #
#                                #
##################################
resource "aws_sfn_state_machine" "state_machine" {
  definition = local.state_definition
  name       = "${local.name_prefix}-state-machine"
  role_arn   = aws_iam_role.state_machine_role.arn
  tags       = local.tags
}

resource "aws_iam_role" "state_machine_role" {
  assume_role_policy = data.aws_iam_policy_document.state_machine_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "lambda_to_state_machine" {
  policy = data.aws_iam_policy_document.lambda_for_state_machine.json
  role   = aws_iam_role.state_machine_role.id
}


###############################################
#                                             #
# set-version                                 #
# ---                                         #
# Lambda function that updates SSM parameters #
# to reference latest application versions    #
#                                             #
###############################################
# Inputs for set-version Lambda
locals {
  common_input_set_version = {
    role_to_assume = "${local.name_prefix}-set-version-cross-account"
    ssm_prefix     = "${local.name_prefix}/versions"
    get_versions   = false
    set_versions   = true

    /*
    # Add your Docker applications here:
    ecr_applications = [
      {
        name        = "${local.name_prefix}-my-docker-app"
        tag_filters = ["master-branch"]
      }
    ]
    */

    /*
    # Add your Lambda applications here:
    lambda_applications = [
      {
        name        = "${local.name_prefix}-my-lambda-app"
        tag_filters = ["master-branch"]
      }
    ]
    # S3 bucket and prefix for Lambda applications
    lambda_s3_bucket = aws_s3_bucket.project_bucket.id
    lambda_s3_prefix = "lambdas"
    */

    /*
    # Add your frontend applications here:
    frontend_applications = [
      {
        name        = "${local.name_prefix}-my-frontend-app"
        tag_filters = ["master-branch"]
      }
    ]
    # S3 bucket and prefix for frontend applications
    frontend_s3_bucket = aws_s3_bucket.project_bucket.id
    frontend_s3_prefix = "frontends"
    */
  }

  get_versions_input_set_version = jsonencode(merge(local.common_input_set_version, {
    get_versions = true
    set_versions = false
  }))
  service_input_set_version = jsonencode(merge(local.common_input_set_version, {
    "versions.$" = "$.versions"
  }))
  test_input_set_version = jsonencode(merge(local.common_input_set_version, {
    account_id   = local.test_account_id
    "versions.$" = "$.versions"
  }))
  stage_input_set_version = jsonencode(merge(local.common_input_set_version, {
    account_id   = local.stage_account_id
    "versions.$" = "$.versions"
  }))
  prod_input_set_version = jsonencode(merge(local.common_input_set_version, {
    account_id   = local.prod_account_id
    "versions.$" = "$.versions"
  }))
}

module "set_version_lambda" {
  source      = "github.com/nsbno/terraform-aws-pipeline-set-version?ref=ee68497"
  name_prefix = local.name_prefix
}

resource "aws_iam_role_policy" "role_to_set_version" {
  role   = module.set_version_lambda.lambda_exec_role_id
  policy = data.aws_iam_policy_document.role_for_set_version.json
}


###############################################
#                                             #
# single-use-fargate-task                     #
# ---                                         #
# Lambda function that can be used to spin up #
# ad-hoc Fargate tasks                        #
#                                             #
###############################################
locals {
  string_templates_single_use_fargate_task = {
    # Reusable shell command for assuming a role
    assume_role = <<EOF
set -eu
temp_role="$(aws sts assume-role --role-arn %s --role-session-name deployment-from-service-account)" \
  && export AWS_ACCESS_KEY_ID="$(echo $temp_role | jq -r .Credentials.AccessKeyId)" \
  && export AWS_SECRET_ACCESS_KEY="$(echo $temp_role | jq -r .Credentials.SecretAccessKey)" \
  && export AWS_SESSION_TOKEN="$(echo $temp_role | jq -r .Credentials.SessionToken)"
EOF
    # Reusable shell command for deploying Terraform
    deploy_terraform = <<EOF
set -eu
cd "%s" \
  && terraform init -lock-timeout=120s -no-color \
  && terraform apply -auto-approve -lock-timeout=120s -no-color
EOF
  }
  common_input_single_use_fargate_task = {
    task_execution_role_arn = module.single_use_fargate_task.task_execution_role_arn
    ecs_cluster             = module.single_use_fargate_task.ecs_cluster_arn
    subnets                 = module.vpc.public_subnet_ids
    state_machine_id        = "${local.name_prefix}-state-machine"
    "content.$"             = "$.deployment_package"
    "token.$"               = "$$.Task.Token",
    "state.$"               = "$$.State.Name"
  }

  service_input_single_use_fargate_task = jsonencode(merge(local.common_input_single_use_fargate_task, {
    task_role_arn = "${local.name_prefix}-single-use-tasks"
    image         = "vydev/terraform:0.12.29"
    cmd_to_run    = "${format(local.string_templates_single_use_fargate_task.assume_role, "arn:aws:iam::${local.service_account_id}:role/${local.name_prefix}-deploy-service-account")} ${format(local.string_templates_single_use_fargate_task.deploy_terraform, "terraform/service")}"
  }))

  test_input_single_use_fargate_task = jsonencode(merge(local.common_input_single_use_fargate_task, {
    task_role_arn = "${local.name_prefix}-single-use-tasks"
    image         = "vydev/terraform:0.12.29"
    cmd_to_run    = "${format(local.string_templates_single_use_fargate_task.assume_role, "arn:aws:iam::${local.test_account_id}:role/${local.name_prefix}-deploy-cross-account")} ${format(local.string_templates_single_use_fargate_task.deploy_terraform, "terraform/test")}"
  }))

  stage_input_single_use_fargate_task = jsonencode(merge(local.common_input_single_use_fargate_task, {
    task_role_arn = "${local.name_prefix}-single-use-tasks"
    image         = "vydev/terraform:0.12.29"
    cmd_to_run    = "${format(local.string_templates_single_use_fargate_task.assume_role, "arn:aws:iam::${local.stage_account_id}:role/${local.name_prefix}-deploy-cross-account")} ${format(local.string_templates_single_use_fargate_task.deploy_terraform, "terraform/stage")}"
  }))

  prod_input_single_use_fargate_task = jsonencode(merge(local.common_input_single_use_fargate_task, {
    task_role_arn = "${local.name_prefix}-single-use-tasks"
    image         = "vydev/terraform:0.12.29"
    cmd_to_run    = "${format(local.string_templates_single_use_fargate_task.assume_role, "arn:aws:iam::${local.prod_account_id}:role/${local.name_prefix}-deploy-cross-account")} ${format(local.string_templates_single_use_fargate_task.deploy_terraform, "terraform/prod")}"
  }))
}

module "single_use_fargate_task" {
  source      = "github.com/nsbno/terraform-aws-single-use-fargate-task?ref=aa61d32"
  name_prefix = local.name_prefix
  tags        = local.tags
}

resource "aws_iam_role" "ecs_task" {
  name               = "${local.name_prefix}-single-use-tasks"
  description        = "A role that can be used by the main container in single-use Fargate task."
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy" "role_to_ecs" {
  policy = data.aws_iam_policy_document.role_for_ecs.json
  role   = aws_iam_role.ecs_task.id
}

resource "aws_iam_role_policy" "logs_to_ecs" {
  policy = data.aws_iam_policy_document.logs_for_ecs.json
  role   = aws_iam_role.ecs_task.id
}

resource "aws_iam_role_policy" "s3_to_ecs" {
  policy = data.aws_iam_policy_document.s3_for_ecs.json
  role   = aws_iam_role.ecs_task.id
}

resource "aws_iam_role_policy" "task_status_to_ecs" {
  policy = data.aws_iam_policy_document.task_status_for_ecs.json
  role   = aws_iam_role.ecs_task.id
}

resource "aws_iam_role_policy" "pass_role_to_single_use_fargate_task" {
  policy = data.aws_iam_policy_document.pass_role_for_single_use_fargate_task.json
  role   = module.single_use_fargate_task.lambda_exec_role_id
}

resource "aws_iam_role" "deploy_service_account" {
  name               = "${local.name_prefix}-deploy-service-account"
  assume_role_policy = data.aws_iam_policy_document.deploy_service_account_assume.json
}

resource "aws_iam_role_policy_attachment" "admin_to_deploy_service_account" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.deploy_service_account.id
}


###############################################
#                                             #
# trigger-pipeline                            #
# ---                                         #
# Lambda function that starts a Step          #
# Functions execution on file upload to S3    #
#                                             #
###############################################
module "trigger_pipeline_lambda" {
  source               = "github.com/nsbno/terraform-aws-trigger-pipeline?ref=8458cde"
  name_prefix          = local.name_prefix
  artifact_bucket_name = aws_s3_bucket.project_bucket.id
  state_machine_arns   = [aws_sfn_state_machine.state_machine.id]
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
  state_machine_arns = [aws_sfn_state_machine.state_machine.id]
  name_prefix        = local.name_prefix
}

# TODO Uncomment and add one per docker container
/*
module "<ecr-container-name>" {
  source      = "github.com/nsbno/terraform-aws-ecr?ref=c25010b"
  name_prefix = "${local.name_prefix}-<container-name>"
  trusted_accounts = local.trusted_accounts
}*/
