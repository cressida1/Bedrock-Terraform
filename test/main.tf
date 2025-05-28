Based on the provided architecture diagram and specifications, here's the Terraform code to create the infrastructure:

```hcl
provider "aws" {
  region = "us-east-1"
}

resource "aws_elastic_beanstalk_application" "ui" {
  name        = "migration-ui"
  description = "UI Application"
}

resource "aws_elastic_beanstalk_environment" "ui" {
  name                = "migration-ui-env"
  application         = aws_elastic_beanstalk_application.ui.name
  solution_stack_name = "64bit Amazon Linux 2 v5.8.0 running Node.js 16"

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
    value     = "2"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "LoadBalanced"
  }
}

resource "aws_elastic_beanstalk_application" "api" {
  name        = "migration-api"
  description = "API Application"
}

resource "aws_elastic_beanstalk_environment" "api" {
  name                = "migration-api-env"
  application         = aws_elastic_beanstalk_application.api.name
  solution_stack_name = "64bit Amazon Linux 2 v5.8.0 running Node.js 16"

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
    value     = "2"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "LoadBalanced"
  }
}

resource "aws_security_group" "api_sg" {
  name        = "api-sg"
  description = "Security group for API"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_elastic_beanstalk_environment.ui.load_balancers[0]]
  }
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

resource "aws_iam_role" "lambda_role" {
  name = "lambda_s3_full_access"

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

resource "aws_iam_role_policy_attachment" "lambda_s3_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_sfn_state_machine" "migration" {
  name     = "Migration"
  role_arn = aws_iam_role.step_function_role.arn

  definition = jsonencode({
    StartAt = "StartMigration"
    States = {
      StartMigration = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.start_migration.arn
        }
        Next = "RollbackMigration"
      }
      RollbackMigration = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.rollback_migration.arn
        }
        End = true
      }
    }
  })
}

resource "aws_iam_role" "step_function_role" {
  name = "step_function_lambda_full_access"

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

resource "aws_iam_role_policy_attachment" "step_function_lambda_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaRole"
  role       = aws_iam_role.step_function_role.name
}

resource "aws_route53_zone" "main" {
  name = "test.com"
}

resource "aws_route53_record" "ui" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "ui.test.com"
  type    = "A"

  alias {
    name                   = aws_elastic_beanstalk_environment.ui.cname
    zone_id                = aws_elastic_beanstalk_environment.ui.load_balancers[0]
    evaluate_target_health = true
  }
}

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_default_subnet" "default_az1" {
  availability_zone = "us-east-1a"
}

resource "aws_default_subnet" "default_az2" {
  availability_zone = "us-east-1b"
}

resource "aws_autoscaling_policy" "ui_cpu_policy" {
  name                   = "ui-cpu-policy"
  autoscaling_group_name = aws_elastic_beanstalk_environment.ui.autoscaling_groups[0]
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
  policy_type            = "SimpleScaling"
}

resource "aws_cloudwatch_metric_alarm" "ui_cpu_alarm" {
  alarm_name          = "ui-cpu-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "75"
  alarm_description   = "This metric monitors EC2 CPU utilization"
  alarm_actions       = [aws_autoscaling_policy.ui_cpu_policy.arn]

  dimensions = {
    AutoScalingGroupName = aws_elastic_beanstalk_environment.ui.autoscaling_groups[0]
  }
}
```

This Terraform code creates the infrastructure based on the provided architecture diagram and specifications. It includes Elastic Beanstalk applications for UI and API, Lambda functions, Step Function, Route53 configuration, and auto-scaling policies. Note that some aspects, like specific EC2 instance configurations, may need to be adjusted based on your exact requirements.