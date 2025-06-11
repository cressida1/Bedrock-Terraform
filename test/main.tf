Based on the architecture diagram and the provided configuration, here's the Terraform code to create the infrastructure:

```hcl
provider "aws" {
  region = "us-east-1"
}

resource "aws_elastic_beanstalk_application" "migration_ui" {
  name        = "migration-ui"
  description = "Migration UI Application"
}

resource "aws_elastic_beanstalk_environment" "migration_ui_env" {
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
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", data.aws_subnets.public.ids)
  }
}

resource "aws_elastic_beanstalk_application" "migration_api" {
  name        = "migration-api"
  description = "Migration API Application"
}

resource "aws_elastic_beanstalk_environment" "migration_api_env" {
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
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", data.aws_subnets.private.ids)
  }
}

resource "aws_security_group_rule" "allow_ui_to_api" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_elastic_beanstalk_environment.migration_ui_env.security_group_id
  security_group_id        = aws_elastic_beanstalk_environment.migration_api_env.security_group_id
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
  name = "lambda_s3_access_role"

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

resource "aws_sfn_state_machine" "migration_state_machine" {
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
  name = "step_function_lambda_role"

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

data "aws_route53_zone" "selected" {
  name = "test.com."
}

resource "aws_route53_record" "migration_ui" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "migration-ui.test.com"
  type    = "A"

  alias {
    name                   = aws_elastic_beanstalk_environment.migration_ui_env.cname
    zone_id                = aws_elastic_beanstalk_environment.migration_ui_env.cname_zone_id
    evaluate_target_health = true
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["false"]
  }
}

resource "aws_autoscaling_policy" "migration_ui_cpu_policy" {
  name                   = "migration-ui-cpu-policy"
  autoscaling_group_name = aws_elastic_beanstalk_environment.migration_ui_env.autoscaling_groups[0]
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 75.0
  }
}

resource "aws_autoscaling_policy" "migration_api_cpu_policy" {
  name                   = "migration-api-cpu-policy"
  autoscaling_group_name = aws_elastic_beanstalk_environment.migration_api_env.autoscaling_groups[0]
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 75.0
  }
}
```

This Terraform code creates the infrastructure based on the provided architecture diagram and configuration. It includes Elastic Beanstalk applications for the UI and API, Lambda functions, Step Functions, Route 53 records, and auto-scaling policies. The code uses the default VPC and subnets, and sets up the necessary IAM roles and security group rules.