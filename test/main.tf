Based on the provided architecture diagram and the requested configuration, here's the Terraform code to create the infrastructure:

```hcl
provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  
  tags = {
    Name = "main-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "Public Subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"

  tags = {
    Name = "Private Subnet"
  }
}

resource "aws_elastic_beanstalk_application" "migration_ui" {
  name        = "Migration-UI"
  description = "Migration UI Application"
}

resource "aws_elastic_beanstalk_environment" "migration_ui" {
  name                = "Migration-UI-env"
  application         = aws_elastic_beanstalk_application.migration_ui.name
  solution_stack_name = "64bit Amazon Linux 2 v5.6.4 running Node.js 14"

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = aws_vpc.main.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = aws_subnet.private.id
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = aws_subnet.public.id
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = "1"
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = "1"
  }
}

resource "aws_elastic_beanstalk_application" "migration_api" {
  name        = "Migration-API"
  description = "Migration API Application"
}

resource "aws_elastic_beanstalk_environment" "migration_api" {
  name                = "Migration-API-env"
  application         = aws_elastic_beanstalk_application.migration_api.name
  solution_stack_name = "64bit Amazon Linux 2 v2.5.4 running .NET Core"

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = aws_vpc.main.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = aws_subnet.private.id
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = aws_subnet.private.id
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = "1"
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = "1"
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_role"

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

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_lambda_function" "get_migration_id" {
  filename      = "get_migration_id.zip"
  function_name = "GetMigrationId-Lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.12"

  vpc_config {
    subnet_ids         = [aws_subnet.private.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
}

resource "aws_lambda_function" "push_records" {
  filename      = "push_records.zip"
  function_name = "PushRecords-Lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.12"

  vpc_config {
    subnet_ids         = [aws_subnet.private.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
}

resource "aws_security_group" "lambda_sg" {
  name        = "lambda_sg"
  description = "Security group for Lambda functions"
  vpc_id      = aws_vpc.main.id
}

resource "aws_sfn_state_machine" "migration_flow" {
  name     = "Migration-Flow"
  role_arn = aws_iam_role.step_function_role.arn

  definition = jsonencode({
    StartAt = "GetMigrationId"
    States = {
      GetMigrationId = {
        Type     = "Task"
        Resource = aws_lambda_function.get_migration_id.arn
        Next     = "PushRecords"
      }
      PushRecords = {
        Type     = "Task"
        Resource = aws_lambda_function.push_records.arn
        End      = true
      }
    }
  })
}

resource "aws_iam_role" "step_function_role" {
  name = "step_function_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "step_function_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaRole"
  role       = aws_iam_role.step_function_role.name
}

resource "aws_cloudwatch_log_group" "eb_ui_logs" {
  name = "/aws/elasticbeanstalk/Migration-UI-env/var/log/eb-activity.log"
}

resource "aws_cloudwatch_log_group" "eb_api_logs" {
  name = "/aws/elasticbeanstalk/Migration-API-env/var/log/eb-activity.log"
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name = "/aws/lambda/GetMigrationId-Lambda"
}

resource "aws_cloudwatch_log_group" "lambda_logs_2" {
  name = "/aws/lambda/PushRecords-Lambda"
}

resource "aws_cloudwatch_log_group" "step_function_logs" {
  name = "/aws/states/Migration-Flow"
}
```

This Terraform code creates the following resources:

1. A VPC with public and private subnets
2. Two Elastic Beanstalk applications and environments (UI and API)
3. Two Lambda functions
4. A Step Function
5. IAM roles and policies
6. Security groups
7. CloudWatch log groups for monitoring

Note that you'll need to provide the actual Lambda function code in ZIP files for the `aws_lambda_function` resources. Also, you may need to adjust the CIDR blocks, region, and other specific details according to your requirements.