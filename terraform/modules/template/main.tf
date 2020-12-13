data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  service_account_id = "<service-account-id>"
  current_account_id = data.aws_caller_identity.current.account_id
  current_region     = data.aws_region.current.name
}

##################################
#                                #
# Cross-account roles used by    #
# service account                #
#                                #
##################################
resource "aws_iam_role" "set_version_cross_account" {
  name               = "${var.name_prefix}-set-version-cross-account"
  assume_role_policy = data.aws_iam_policy_document.cross_account_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "ssm_to_set_version" {
  policy = data.aws_iam_policy_document.ssm_for_set_version.json
  role   = aws_iam_role.set_version_cross_account.id
}

resource "aws_iam_role" "deploy_cross_account" {
  name               = "${var.name_prefix}-deploy-cross-account"
  assume_role_policy = data.aws_iam_policy_document.deploy_cross_account_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "admin_to_deploy_cross_account" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.deploy_cross_account.id
}

