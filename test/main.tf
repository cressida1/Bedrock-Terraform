Based on the architecture diagram and the provided JSON configuration, here's the Terraform code to create the infrastructure:

```hcl
provider "aws" {
  region = "us-east-1"
}

resource "aws_elastic_beanstalk_application" "ui_app" {
  name        = "migration-ui"
  description = "UI Application"
}

resource "aws_elastic_beanstalk_environment" "ui_env" {
  name                = "migration-ui-env"
  application         = aws_elastic_beanstalk_application.ui_app.name
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
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = "public_subnet_id"  # Replace with actual public subnet ID
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.ui_instance_profile.name
  }
}

resource "aws_elastic_beanstalk_application" "api_app" {
  name        = "migration-api"
  description = "API Application"
}

resource "aws_elastic_beanstalk_environment" "api_env" {
  name                = "migration-api-env"
  application         = aws_elastic_beanstalk_application.api_app.name
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
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = "private_subnet_id"  # Replace with actual private subnet ID
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.api_instance_profile.name
  }
}

resource "aws_security_group_rule" "api_ingress" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_elastic_beanstalk_environment.ui_env.load_balancers[0]
  security_group_id        = aws_elastic_beanstalk_environment.api_env.security_groups[0]
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

resource "aws_sfn_state_machine" "migration_state_machine" {
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

resource "aws_route53_record" "ui_alias" {
  zone_id = "ZONE_ID"  # Replace with actual hosted zone ID
  name    = "test.com"
  type    = "A"

  alias {
    name                   = aws_elastic_beanstalk_environment.ui_env.cname
    zone_id                = aws_elastic_beanstalk_environment.ui_env.load_balancers[0]
    evaluate_target_health = true
  }
}

resource "aws_autoscaling_policy" "ui_scaling_policy" {
  name                   = "ui-scaling-policy"
  autoscaling_group_name = aws_elastic_beanstalk_environment.ui_env.autoscaling_groups[0]
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 75.0
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

resource "aws_iam_instance_profile" "ui_instance_profile" {
  name = "ui_instance_profile"
  role = aws_iam_role.ui_instance_role.name
}

resource "aws_iam_role" "ui_instance_role" {
  name = "ui_instance_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "api_instance_profile" {
  name = "api_instance_profile"
  role = aws_iam_role.api_instance_role.name
}

resource "aws_iam_role" "api_instance_role" {
  name = "api_instance_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}
```

This Terraform code creates the main components of the architecture as described in the diagram and JSON configuration. Note that you'll need to replace some placeholder values (like subnet IDs and hosted zone ID) with actual values from your AWS account. Also, you may need to adjust the Elastic Beanstalk solution stack names based on your specific requirements.