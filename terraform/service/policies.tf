data "aws_iam_policy_document" "s3_for_accounts" {
  statement {
    effect    = "Allow"
    actions   = ["s3:Get*", "s3:List*"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = formatlist("arn:aws:iam::%s:root", local.trusted_accounts)
    }
  }
}

data "aws_iam_policy_document" "sfn_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["states.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "lambda_for_sfn" {
  statement {
    effect  = "Allow"
    actions = ["lambda:InvokeFunction"]
    resources = [
      "arn:aws:lambda:${local.current_region}:${local.current_account_id}:function:${module.set_version.function_name}",
      "arn:aws:lambda:${local.current_region}:${local.current_account_id}:function:${module.single_use_fargate_task.function_name}",
      "arn:aws:lambda:${local.current_region}:${local.current_account_id}:function:${module.error_catcher.function_name}"
    ]
  }
}

data "aws_iam_policy_document" "pass_role_for_single_use_fargate_task" {
  statement {
    effect = "Allow"
    actions = [
      "iam:PassRole",
    ]
    resources = [aws_iam_role.fargate_task.arn]
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

data "aws_iam_policy_document" "role_assume_for_fargate_task" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = formatlist("arn:aws:iam::%s:role/${aws_iam_role.deployment.name}", local.trusted_accounts)
  }
}

data "aws_iam_policy_document" "s3_for_fargate_task" {
  statement {
    effect    = "Allow"
    actions   = ["s3:Get*", "s3:List*"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
  }
}

data "aws_iam_policy_document" "logs_for_fargate_task" {
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

data "aws_iam_policy_document" "task_status_for_fargate_task" {
  statement {
    effect = "Allow"
    actions = [
      "states:SendTaskSuccess",
      "states:SendTaskFailure"
    ]
    resources = local.state_machine_arns
  }
}

data "aws_iam_policy_document" "metrics_for_fargate_task" {
  statement {
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["${local.name_prefix}-single-use-tasks"]
    }
  }
}

data "aws_iam_policy_document" "role_assume_for_set_version" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = formatlist("arn:aws:iam::%s:role/${local.name_prefix}-trusted-set-version", local.trusted_accounts)
  }
}


data "aws_iam_policy_document" "trusted_account_deployment_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.service_account_id}:role/${local.name_prefix}-single-use-tasks"]
    }
  }
}
