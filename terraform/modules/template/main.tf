data "aws_caller_identity" "this" {}
data "aws_region" "this" {}

locals {
  service_account_id = "<service-account-id>"
  trusted_accounts = [
    local.service_account_id
  ]
  current_account_id     = data.aws_caller_identity.this.account_id
  current_region         = data.aws_region.this.name
  fargate_task_role_name = "${var.name_prefix}-single-use-tasks"
}


###################################################
#                                                 #
# Roles that can be assumed from trusted accounts #
# (typically a `service` account)                 #
#                                                 #
###################################################
resource "aws_iam_role" "deployment" {
  description        = "A role that can be assumed by a Fargate task during a deployment"
  name               = "${var.name_prefix}-trusted-deployment"
  assume_role_policy = data.aws_iam_policy_document.trusted_account_deployment_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "admin_to_deployment" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.deployment.id
}

resource "aws_iam_role" "set_version" {
  description        = "A role that can be assumed by trusted accounts during a deployment in order to update SSM parameters containing application artifact versions."
  name               = "${var.name_prefix}-trusted-set-version"
  assume_role_policy = data.aws_iam_policy_document.trusted_account_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "ssm_to_set_version" {
  policy = data.aws_iam_policy_document.ssm_for_set_version.json
  role   = aws_iam_role.set_version.id
}
