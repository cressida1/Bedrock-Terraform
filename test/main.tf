Here's the Terraform code to create the described AWS serverless architecture:

```hcl
provider "aws" {
  region = "us-west-2"  # Change this to your preferred region
}

resource "aws_sqs_queue" "migration_queue" {
  name                        = "migration-queue.fifo"
  fifo_queue                  = true
  content_based_deduplication = true

  tags = {
    Name = "migration-queue"
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "migration_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_full_access" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_lambda_function" "migration_lambda" {
  filename      = "lambda_function.zip"  # Create this zip file with your Lambda code
  function_name = "migration-lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.handler"
  runtime       = "python3.9"  # Use the latest stable Python version

  timeout     = 900  # 15 minutes
  memory_size = 128  # Default memory size

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.migration_table.name
    }
  }

  tags = {
    Name = "migration-lambda"
  }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.migration_queue.arn
  function_name    = aws_lambda_function.migration_lambda.arn
}

resource "aws_dynamodb_table" "migration_table" {
  name           = "migration-table"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "migration-id"

  attribute {
    name = "migration-id"
    type = "S"
  }

  tags = {
    Name = "migration-table"
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.migration_lambda.function_name}"
  retention_in_days = 14

  tags = {
    Name = "migration-lambda-logs"
  }
}
```

This Terraform code creates the following resources:

1. A FIFO SQS queue named "migration-queue"
2. An IAM role for the Lambda function with DynamoDB full access
3. A Lambda function named "migration-lambda" with the specified configuration
4. An event source mapping to trigger the Lambda function from the SQS queue
5. A DynamoDB table named "migration-table" with "migration-id" as the primary key
6. A CloudWatch log group for the Lambda function

Make sure to create a `lambda_function.zip` file containing your Lambda function code before applying this Terraform configuration. Also, adjust the AWS region in the provider block if needed.