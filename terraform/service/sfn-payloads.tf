#####################################
#                                   #
# Common payloads for set-version   #
# that can be used across pipelines #
#                                   #
#####################################
locals {
  sfn_common_set_version_payload = {
    role_to_assume = "${local.name_prefix}-trusted-set-version"
    ssm_prefix     = "${local.name_prefix}/versions"
    get_versions   = false
    set_versions   = true
    ecr_applications = [
      /* Add your Docker applications here.
      {
        name        = "${local.name_prefix}-my-docker-app"
        tag_filters = ["master-branch"]
      }
      */
    ]
    lambda_applications = [
      /* Add your Lambda applications here.
      {
        name        = "${local.name_prefix}-my-lambda-app"
        tag_filters = ["master-branch"]
      }
      */
    ]
    lambda_s3_bucket = aws_s3_bucket.artifacts.id
    lambda_s3_prefix = "lambdas"
    frontend_applications = [
      /* Add your frontend applications here.
      {
        name        = "${local.name_prefix}-my-frontend-app"
        tag_filters = ["master-branch"]
      }
      */
    ]
    frontend_s3_bucket = aws_s3_bucket.artifacts.id
    frontend_s3_prefix = "frontends"
  }

  sfn_common_set_version_payloads = {
    initial = merge(local.sfn_common_set_version_payload, {
      get_versions = true
      set_versions = false
    })
    service = merge(local.sfn_common_set_version_payload, {
      "versions.$" = "$.versions"
    })
    test = merge(local.sfn_common_set_version_payload, {
      account_id   = local.test_account_id
      "versions.$" = "$.versions"
    })
    stage = merge(local.sfn_common_set_version_payload, {
      account_id   = local.stage_account_id
      "versions.$" = "$.versions"
    })
    prod = merge(local.sfn_common_set_version_payload, {
      account_id   = local.prod_account_id
      "versions.$" = "$.versions"
    })
  }
}


###############################################
#                                             #
# Common payloads for single-use-fargate-task #
# that can be used across pipelines           #
#                                             #
###############################################
locals {
  sfn_shell_helpers = {
    assume_role      = "aws configure set profile.deployment.credential_source \"EcsContainer\" && aws configure set profile.deployment.region \"${local.current_region}\" && aws configure set profile.deployment.role_session_name \"deployment-from-service-account\" && aws configure set profile.deployment.role_arn \"%s\" && export AWS_PROFILE=deployment"
    terraform_deploy = "terraform init -no-color && terraform apply -auto-approve -lock-timeout=120s -no-color"
    terraform_plan   = "terraform init -no-color && terraform plan -lock-timeout=120s -no-color"
  }
  sfn_common_fargate_payload = {
    task_role_arn           = aws_iam_role.fargate_task.arn # Default task role
    task_execution_role_arn = module.single_use_fargate_task.task_execution_role_arn
    ecs_cluster             = module.single_use_fargate_task.ecs_cluster_arn
    subnets                 = module.vpc.public_subnet_ids
    "content.$"             = "$.deployment_package"
    "token.$"               = "$$.Task.Token",
    "log_stream_prefix.$"   = "States.Format('{}/{}/{}', $$.StateMachine.Name, $$.Execution.Name, $$.State.Name)"
    metric_namespace        = "${local.name_prefix}-single-use-tasks"
    metric_dimensions = {
      "StateMachineName.$" = "$$.StateMachine.Name"
      "StateName.$"        = "$$.State.Name"
    }
  }

  sfn_common_fargate_payloads = {
    service = merge(local.sfn_common_fargate_payload, {
      image      = "vydev/terraform:1.0.0"
      cmd_to_run = "${format(local.sfn_shell_helpers.assume_role, "arn:aws:iam::${local.service_account_id}:role/${local.name_prefix}-trusted-deployment")} && cd terraform/service && ${local.sfn_shell_helpers.terraform_deploy}"
    })
    test = merge(local.sfn_common_fargate_payload, {
      image      = "vydev/terraform:1.0.0"
      cmd_to_run = "${format(local.sfn_shell_helpers.assume_role, "arn:aws:iam::${local.test_account_id}:role/${local.name_prefix}-trusted-deployment")} && cd terraform/test && ${local.sfn_shell_helpers.terraform_deploy}"
    })
    stage = merge(local.sfn_common_fargate_payload, {
      image      = "vydev/terraform:1.0.0"
      cmd_to_run = "${format(local.sfn_shell_helpers.assume_role, "arn:aws:iam::${local.stage_account_id}:role/${local.name_prefix}-trusted-deployment")} && cd terraform/stage && ${local.sfn_shell_helpers.terraform_deploy}"
    })
    prod = merge(local.sfn_common_fargate_payload, {
      image      = "vydev/terraform:1.0.0"
      cmd_to_run = "${format(local.sfn_shell_helpers.assume_role, "arn:aws:iam::${local.prod_account_id}:role/${local.name_prefix}-trusted-deployment")} && cd terraform/prod && ${local.sfn_shell_helpers.terraform_deploy}"
    })
  }
}
