# CloudFormation
You can use the CloudFormation template `cfn_bootstrap.yml` to create the S3 state bucket and DynamoDB lock table required by Terraform. A stack must be created in each account.

The stack can easily be created by logging in to the correct AWS account on the command-line, and then using the AWS CLI:
```sh
aws cloudformation create-stack \
  --stack-name "TerraformBootstrap" \
  --template-body file://cfn_bootstrap.yml \
  && aws cloudformation wait \
    stack-create-complete \
    --stack-name "TerraformBootstrap" \
  && aws cloudformation describe-stacks \
    --stack-name "TerraformBootstrap" \
    --query "Stacks[*].Outputs"
```
