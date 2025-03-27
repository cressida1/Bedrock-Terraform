Based on the architecture diagram and your requirements, I'll provide the Terraform code split into separate files as requested. Here's the Infrastructure-as-Code (IaC) implementation using Terraform:

main.tf:
```hcl
provider "aws" {
  region = var.aws_region
}
```

backend.tf:
```hcl
terraform {
  backend "s3" {
    bucket = "YOUR_S3_BUCKET_NAME"
    key    = "terraform/state"
    region = "us-west-2"
    encrypt = true
  }
}
```

variables.tf:
```hcl
variable "aws_region" {
  description = "AWS region for resources"
  default     = "us-west-2"
}

variable "queue_name" {
  description = "Name of the SQS FIFO queue"
  default     = "migration-queue.fifo"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  default     = "migration-lambda"
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  default     = "migration-table"
}
```

sqs.tf:
```hcl
resource "aws_sqs_queue" "migration_queue" {
  name                        = var.queue_name
  fifo_queue                  = true
  content_based_deduplication = true

  tags = {
    Name = "Migration Queue"
  }
}
```

lambda.tf:
```hcl
resource "aws_lambda_function" "migration_lambda" {
  filename         = "lambda_function.zip"
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.8"
  timeout          = 900 # 15 minutes

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.migration_table.name
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.migration_queue.arn
  function_name    = aws_lambda_function.migration_lambda.arn
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.migration_lambda.function_name}"
  retention_in_days = 14
}
```

dynamodb.tf:
```hcl
resource "aws_dynamodb_table" "migration_table" {
  name           = var.dynamodb_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "migration-id"

  attribute {
    name = "migration-id"
    type = "S"
  }

  tags = {
    Name = "Migration Table"
  }
}
```

iam.tf:
```hcl
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

resource "aws_iam_role_policy_attachment" "lambda_sqs_full_access" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}
```

outputs.tf:
```hcl
output "sqs_queue_url" {
  description = "URL of the SQS queue"
  value       = aws_sqs_queue.migration_queue.url
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.migration_lambda.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.migration_table.name
}
```

This Terraform code creates the necessary resources for the serverless architecture shown in the diagram, including an SQS FIFO queue, a Lambda function, a DynamoDB table, and the required IAM roles and policies. The code is split into separate files for better organization and maintainability.