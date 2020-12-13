data "aws_iam_policy_document" "s3_for_accounts" {
  statement {
    effect    = "Allow"
    actions   = ["s3:Get*", "s3:List*"]
    resources = [aws_s3_bucket.project_bucket.arn, "${aws_s3_bucket.project_bucket.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = formatlist("arn:aws:iam::%s:root", local.trusted_accounts)
    }
  }
}

data "aws_iam_policy_document" "state_machine_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["states.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "lambda_for_state_machine" {
  statement {
    effect  = "Allow"
    actions = ["lambda:InvokeFunction"]
    resources = [
      "arn:aws:lambda:${local.current_region}:${local.current_account_id}:function:*"
    ]
  }
}

data "aws_iam_policy_document" "pass_role_for_single_use_fargate_task" {
  statement {
    effect = "Allow"
    actions = [
      "iam:PassRole",
      "iam:GetRole"
    ]
    resources = [
      aws_iam_role.ecs_task.arn,
      module.single_use_fargate_task.task_execution_role_arn
    ]
  }
}

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ecs-tasks.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "role_for_ecs" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "s3_for_ecs" {
  statement {
    effect    = "Allow"
    actions   = ["s3:Get*", "s3:List*"]
    resources = [aws_s3_bucket.project_bucket.arn, "${aws_s3_bucket.project_bucket.arn}/*"]
  }
}

data "aws_iam_policy_document" "logs_for_ecs" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup"]
    resources = ["arn:aws:logs:${local.current_region}:${local.current_account_id}:*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${local.current_region}:${local.current_account_id}:log-group:/aws/ecs/*"
    ]
  }
}

data "aws_iam_policy_document" "task_status_for_ecs" {
  statement {
    effect = "Allow"
    actions = [
      "states:SendTaskSuccess",
      "states:SendTaskFailure"
    ]
    resources = [
      aws_sfn_state_machine.state_machine.id
    ]
  }
}

data "aws_iam_policy_document" "role_for_set_version" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::*:role/${local.name_prefix}-set-version-cross-account"]
  }
}


data "aws_iam_policy_document" "deploy_service_account_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.service_account_id}:role/${local.name_prefix}-single-use-tasks"]
    }
  }
}
