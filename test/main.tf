```hcl
# SQS FIFO Queue
resource "aws_sqs_queue" "migration_queue" {
  name                       = "migration-queue"
  fifo_queue                 = true
  content_based_deduplication = true
}

# IAM Role for Lambda
data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "migration_lambda_role" {
  name               = "migration-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  ]
}

# Lambda Function
resource "aws_lambda_function" "migration_lambda" {
  filename         = "lambda_function_payload.zip"
  function_name    = "migration-lambda"
  role             = aws_iam_role.migration_lambda_role.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.9"
  timeout          = 900
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  event_source_mapping {
    event_source_arn = aws_sqs_queue.migration_queue.arn
    batch_size       = 1
  }
}

resource "aws_cloudwatch_log_group" "migration_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.migration_lambda.function_name}"
  retention_in_days = 7
}

# DynamoDB Table
resource "aws_dynamodb_table" "migration_table" {
  name           = "migration-table"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "migration-id"

  attribute {
    name = "migration-id"
    type = "S"
  }
}
```

This Terraform code defines the following resources:

1. An SQS FIFO Queue named "migration-queue"
2. An IAM Role for the Lambda function with DynamoDB full access
3. A Lambda function named "migration-lambda" with the provided Python code, triggered by the SQS queue
4. A CloudWatch Log Group for the Lambda function logs
5. A DynamoDB table named "migration-table" with a hash key of "migration-id"

Note: You will need to provide the actual Python code for the Lambda function in the "lambda_function_payload.zip" file.