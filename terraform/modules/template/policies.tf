data "aws_iam_policy_document" "cross_account_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.service_account_id}:root"]
    }
  }
}

data "aws_iam_policy_document" "ssm_for_set_version" {
  statement {
    effect    = "Allow"
    actions   = ["ssm:PutParameter"]
    resources = ["arn:aws:ssm:${local.current_region}:${local.current_account_id}:parameter/${var.name_prefix}/versions/*"]
  }
}

data "aws_iam_policy_document" "deploy_cross_account_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.service_account_id}:root"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::${local.service_account_id}:role/${var.name_prefix}-single-use-tasks"]
    }
  }
}

