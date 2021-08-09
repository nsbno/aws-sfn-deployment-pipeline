{
  "Comment": "A deployment pipeline implemented as a state machine",
  "StartAt": "Get Latest Artifact Versions",
  "States": {
    "Get Latest Artifact Versions": {
      "Comment": "Get the latest versions of application artifacts in S3 and ECR",
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${set_version.function_name}",
        "Payload": ${set_version.payloads.initial}
      },
      "ResultSelector": {
        "ecr.$": "$.Payload.ecr",
        "frontend.$": "$.Payload.frontend",
        "lambda.$": "$.Payload.lambda"
      },
      "ResultPath": "$.versions",
      "Next": "Deploy to Test and Stage"
    },
    "Deploy to Test and Stage": {
      "Comment": "Parallel deployment to test and stage environments",
      "Type": "Parallel",
      "Next": "Raise Errors",
      "ResultPath": "$.result",
      "Branches": [
        {
          "StartAt": "Bump Versions in Test",
          "States": {
            "Bump Versions in Test": {
              "Comment": "Update SSM parameters in test environment to latest versions of applications artifacts",
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "Parameters": {
                "FunctionName": "${set_version.function_name}",
                "Payload": ${set_version.payloads.test}
              },
              "Catch": [{
                "ErrorEquals": ["States.ALL"],
                "Next": "Catch Test Errors"
              }],
              "ResultPath": null,
              "Next": "Deploy Test"
            },
            "Deploy Test": {
              "Type": "Task",
              "Comment": "Spins up a single-use Fargate task and deploys to the test environment",
              "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
              "Parameters": {
                "FunctionName": "${fargate_task.function_name}",
                "Payload": ${fargate_task.payloads.test}
              },
              "Catch": [{
                "ErrorEquals": ["States.ALL"],
                "Next": "Catch Test Errors"
              }],
              "OutputPath": null,
              "ResultPath": null,
              "TimeoutSeconds": 3600,
              "End": true
            },
            "Catch Test Errors": {
              "Type": "Pass",
              "End": true
            }
          }
        },
        {
          "StartAt": "Bump Versions in Stage",
          "States": {
            "Bump Versions in Stage": {
              "Comment": "Update SSM parameters in stage environment to latest versions of applications artifacts",
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "Parameters": {
                "FunctionName": "${set_version.function_name}",
                "Payload": ${set_version.payloads.stage}
              },
              "Catch": [{
                "ErrorEquals": ["States.ALL"],
                "Next": "Catch Stage Errors"
              }],
              "ResultPath": null,
              "Next": "Deploy Stage"
            },
            "Deploy Stage": {
              "Type": "Task",
              "Comment": "Spins up a single-use Fargate task and deploys to the stage environment",
              "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
              "Parameters": {
                "FunctionName": "${fargate_task.function_name}",
                "Payload": ${fargate_task.payloads.stage}
              },
              "Catch": [{
                "ErrorEquals": ["States.ALL"],
                "Next": "Catch Stage Errors"
              }],
              "ResultPath": null,
              "TimeoutSeconds": 3600,
              "Next": "Integration Tests"
            },
            "Integration Tests": {
              "Type": "Wait",
              "Seconds": 7,
              "OutputPath": null,
              "End": true
            },
            "Catch Stage Errors": {
              "Type": "Pass",
              "End": true
            }
          }
        },
        {
          "StartAt": "Bump Versions in Service",
          "States": {
            "Bump Versions in Service": {
              "Comment": "Update SSM parameters in service environment to latest versions of applications artifacts",
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "Parameters": {
                "FunctionName": "${set_version.function_name}",
                "Payload": ${set_version.payloads.service}
              },
              "Catch": [{
                "ErrorEquals": ["States.ALL"],
                "Next": "Catch Service Errors"
              }],
              "ResultPath": null,
              "Next": "Deploy Service"
            },
            "Deploy Service": {
              "Type": "Task",
              "Comment": "Spins up a single-use Fargate task and deploys to the service environment",
              "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
              "Parameters": {
                "FunctionName": "${fargate_task.function_name}",
                "Payload": ${fargate_task.payloads.service}
              },
              "Catch": [{
                "ErrorEquals": ["States.ALL"],
                "Next": "Catch Service Errors"
              }],
              "OutputPath": null,
              "ResultPath": null,
              "TimeoutSeconds": 3600,
              "End": true
            },
            "Catch Service Errors": {
              "Type": "Pass",
              "End": true
            }
          }
        }
      ]
    },
    "Raise Errors":{
      "Comment": "Raise previously caught errors, if any",
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
      "Parameters": {
        "FunctionName": "${error_catcher.function_name}",
        "Payload":  {
          "token.$": "$$.Task.Token",
          "input.$": "$.result"
        }
      },
      "ResultPath": "$.errors_found",
      "TimeoutSeconds": 3600,
      "Next": "Bump Versions in Prod"
    },
    "Bump Versions in Prod": {
      "Comment": "Update SSM parameters in prod environment to latest versions of applications artifacts",
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${set_version.function_name}",
        "Payload": ${set_version.payloads.prod}
      },
      "ResultPath": null,
      "Next": "Deploy Prod"
    },
    "Deploy Prod":{
      "Type": "Task",
      "Comment": "Spins up a single-use Fargate task and deploys to the prod environment",
      "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
      "Parameters": {
        "FunctionName": "${fargate_task.function_name}",
        "Payload": ${fargate_task.payloads.prod}
      },
      "ResultPath": null,
      "TimeoutSeconds": 3600,
      "Next": "Smoke Tests"
    },
    "Smoke Tests": {
      "Type": "Wait",
      "Seconds": 7,
      "End": true
    }
  }
}
