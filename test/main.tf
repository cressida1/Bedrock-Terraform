Based on the architecture diagram and the provided configuration, here's the Terraform code to create the infrastructure:

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
  name        = "migration-ui"
  description = "Migration UI Application"
}

resource "aws_elastic_beanstalk_environment" "migration_ui" {
  name                = "migration-ui-env"
  application         = aws_elastic_beanstalk_application.migration_ui.name
  solution_stack_name = "64bit Amazon Linux 2 v5.8.0 running Node.js 14"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t2.medium"
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

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = aws_vpc.main.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = aws_subnet.public.id
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }
}

resource "aws_elastic_beanstalk_application" "migration_api" {
  name        = "migration-api"
  description = "Migration API Application"
}

resource "aws_elastic_beanstalk_environment" "migration_api" {
  name                = "migration-api-env"
  application         = aws_elastic_beanstalk_application.migration_api.name
  solution_stack_name = "64bit Amazon Linux 2 v5.8.0 running Node.js 14"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t2.medium"
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
}

resource "aws_security_group" "migration_api" {
  name        = "migration-api-sg"
  description = "Security group for Migration API"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_elastic_beanstalk_environment.migration_ui.load_balancers[0]]
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

resource "aws_iam_role_policy_attachment" "lambda_s3_full_access" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_lambda_function" "start_migration" {
  filename      = "start_migration.zip"
  function_name = "start-migration"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.13"
  timeout       = 900
}

resource "aws_lambda_function" "rollback_migration" {
  filename      = "rollback_migration.zip"
  function_name = "rollback-migration"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.13"
  timeout       = 900
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

resource "aws_iam_role_policy_attachment" "step_function_lambda_full_access" {
  policy_arn = "arn:aws:iam::aws:policy/AWSLambdaFullAccess"
  role       = aws_iam_role.step_function_role.name
}

resource "aws_sfn_state_machine" "migration" {
  name     = "Migration"
  role_arn = aws_iam_role.step_function_role.arn

  definition = jsonencode({
    StartAt = "StartMigration"
    States = {
      StartMigration = {
        Type     = "Task"
        Resource = aws_lambda_function.start_migration.arn
        Next     = "RollbackMigration"
      }
      RollbackMigration = {
        Type     = "Task"
        Resource = aws_lambda_function.rollback_migration.arn
        End      = true
      }
    }
  })
}

resource "aws_route53_zone" "main" {
  name = "test.com"
}

resource "aws_route53_record" "migration_ui" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "migration-ui.test.com"
  type    = "A"

  alias {
    name                   = aws_elastic_beanstalk_environment.migration_ui.cname
    zone_id                = aws_elastic_beanstalk_environment.migration_ui.load_balancers[0]
    evaluate_target_health = true
  }
}

resource "aws_autoscaling_policy" "cpu_utilization" {
  name                   = "cpu-utilization"
  autoscaling_group_name = aws_elastic_beanstalk_environment.migration_ui.autoscaling_groups[0]
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 75.0
  }
}
```

This Terraform code creates the infrastructure based on the provided architecture diagram and configuration. It includes the VPC, subnets, Elastic Beanstalk applications and environments, Lambda functions, Step Function, Route 53 records, and auto-scaling policies. Note that some aspects, like the specific AMI for EC2 instances, are managed by Elastic Beanstalk and not directly specified in this code.