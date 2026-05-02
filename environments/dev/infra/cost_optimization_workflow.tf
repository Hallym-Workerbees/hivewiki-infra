data "aws_caller_identity" "current" {}

##############
# Hibernator #
##############
resource "aws_secretsmanager_secret" "hive_hibernate" {
  name        = "${var.cluster_name}-hive-hibernate"
  description = "Incoming webhook url"
}

resource "aws_iam_role" "hibernate" {
  name = "${var.cluster_name}-hibernate"

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

data "aws_iam_policy_document" "hibernate_permissions" {
  statement {
    sid    = "AllowHibernateStartLambdaInvoke"
    effect = "Allow"

    actions = [
      "lambda:InvokeFunction"
    ]

    resources = [
      aws_lambda_function.hibernate_start.arn,
      aws_lambda_function.flush_elasticache.arn,
      aws_lambda_function.hibernate_complete.arn
    ]
  }

  statement {
    sid    = "AllowRdsHibernate"
    effect = "Allow"

    actions = [
      "rds:DescribeDBInstances",
      "rds:StopDBInstance"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowEksHibernate"
    effect = "Allow"

    actions = [
      "eks:DescribeNodegroup",
      "eks:UpdateNodegroupConfig"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowNetworkHibernateCodeBuild"
    effect = "Allow"

    actions = [
      "codebuild:StartBuild",
      "codebuild:BatchGetBuilds",
      "codebuild:StopBuild"
    ]

    resources = [
      aws_codebuild_project.hibernate_network.arn
    ]
  }

  statement {
    sid    = "AllowStepFunctionsManagedEventsRule"
    effect = "Allow"

    actions = [
      "events:PutRule",
      "events:PutTargets",
      "events:DescribeRule"
    ]

    resources = [
      "arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventForCodeBuild*"
    ]
  }
}

resource "aws_iam_role_policy" "hibernate_permissions" {
  name   = "${var.cluster_name}-hibernate-permissions"
  role   = aws_iam_role.hibernate.id
  policy = data.aws_iam_policy_document.hibernate_permissions.json
}

resource "aws_sfn_state_machine" "hibernate" {
  name     = "${var.cluster_name}-hibernate"
  role_arn = aws_iam_role.hibernate.arn

  definition = jsonencode({
    Comment = "${var.cluster_name} Cloud resource minimizer during off-hours"
    StartAt = "SendHibernateStart"

    States = {
      SendHibernateStart = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"

        Parameters = {
          FunctionName = aws_lambda_function.hibernate_start.arn
          Payload = {
            "execution_arn.$"  = "$$.Execution.Id"
            "execution_name.$" = "$$.Execution.Name"
            "started_at.$"     = "$$.Execution.StartTime"
            "cluster_name"     = var.cluster_name
          }
        }

        ResultPath = "$.hibernate_start"
        Next       = "HibernateComputes"
      }

      HibernateComputes = {
        Type = "Parallel"

        Branches = [
          {
            StartAt = "CheckRdsStatus"

            States = {
              CheckRdsStatus = {
                Type     = "Task"
                Resource = "arn:aws:states:::aws-sdk:rds:describeDBInstances"

                Parameters = {
                  DbInstanceIdentifier = module.rds.db_identifier
                }

                ResultPath = "$.rds_describe"
                Next       = "ShouldStopRds"
              }

              ShouldStopRds = {
                Type = "Choice"

                Choices = [
                  {
                    And = [
                      {
                        Variable  = "$.rds_describe.DbInstances[0].DbInstanceStatus"
                        IsPresent = true
                      },
                      {
                        Variable     = "$.rds_describe.DbInstances[0].DbInstanceStatus"
                        StringEquals = "available"
                      }
                    ]
                    Next = "StopRds"
                  }
                ]

                Default = "SkipRds"
              }

              StopRds = {
                Type     = "Task"
                Resource = "arn:aws:states:::aws-sdk:rds:stopDBInstance"

                Parameters = {
                  DbInstanceIdentifier = module.rds.db_identifier
                }

                ResultPath = "$.rds_stop"
                Next       = "RdsStoppedResult"
              }

              RdsStoppedResult = {
                Type = "Pass"

                Parameters = {
                  service                = "rds"
                  action                 = "stopped"
                  db_instance_identifier = module.rds.db_identifier
                  "previous_status.$"    = "$.rds_describe.DbInstances[0].DbInstanceStatus"
                }

                End = true
              }

              SkipRds = {
                Type = "Pass"

                Parameters = {
                  service                = "rds"
                  action                 = "skipped"
                  reason                 = "RDS is not available"
                  db_instance_identifier = module.rds.db_identifier
                  "previous_status.$"    = "$.rds_describe.DbInstances[0].DbInstanceStatus"
                }

                End = true
              }
            }
          },

          {
            StartAt = "CheckEksNodegroup"

            States = {
              CheckEksNodegroup = {
                Type     = "Task"
                Resource = "arn:aws:states:::aws-sdk:eks:describeNodegroup"

                Parameters = {
                  ClusterName   = module.eks_cluster.cluster_name
                  NodegroupName = module.eks_node_group.ng_name
                }

                ResultPath = "$.eks_nodegroup"
                Next       = "ShouldScaleDownEks"
              }

              ShouldScaleDownEks = {
                Type = "Choice"
                Choices = [
                  {
                    And = [
                      {
                        Variable  = "$.eks_nodegroup.Nodegroup.ScalingConfig.DesiredSize"
                        IsPresent = true
                      },
                      {
                        Variable           = "$.eks_nodegroup.Nodegroup.ScalingConfig.DesiredSize"
                        NumericGreaterThan = 0
                      }
                    ]
                    Next = "ScaleDownEks"
                  }
                ]
                Default = "SkipEks"
              }

              ScaleDownEks = {
                Type     = "Task"
                Resource = "arn:aws:states:::aws-sdk:eks:updateNodegroupConfig"

                Parameters = {
                  ClusterName   = module.eks_cluster.cluster_name
                  NodegroupName = module.eks_node_group.ng_name

                  ScalingConfig = {
                    MinSize     = 0
                    DesiredSize = 0
                  }
                }

                ResultPath = "$.eks_scale_down"
                Next       = "EksScaledDownResult"
              }

              EksScaledDownResult = {
                Type = "Pass"

                Parameters = {
                  service              = "eks"
                  action               = "scaled_down"
                  cluster_name         = module.eks_cluster.cluster_name
                  nodegroup_name       = module.eks_node_group.ng_name
                  "previous_min.$"     = "$.eks_nodegroup.Nodegroup.ScalingConfig.MinSize"
                  "previous_desired.$" = "$.eks_nodegroup.Nodegroup.ScalingConfig.DesiredSize"
                  "previous_max.$"     = "$.eks_nodegroup.Nodegroup.ScalingConfig.MaxSize"
                  target_min           = 0
                  target_desired       = 0
                }

                End = true
              }

              SkipEks = {
                Type = "Pass"

                Parameters = {
                  service              = "eks"
                  action               = "skipped"
                  reason               = "EKS nodegroup desired size is already 0"
                  cluster_name         = module.eks_cluster.cluster_name
                  nodegroup_name       = module.eks_node_group.ng_name
                  "previous_min.$"     = "$.eks_nodegroup.Nodegroup.ScalingConfig.MinSize"
                  "previous_desired.$" = "$.eks_nodegroup.Nodegroup.ScalingConfig.DesiredSize"
                  "previous_max.$"     = "$.eks_nodegroup.Nodegroup.ScalingConfig.MaxSize"
                }

                End = true
              }
            }
          },

          {
            StartAt = "FlushElasticacheServerless"

            States = {
              FlushElasticacheServerless = {
                Type     = "Task"
                Resource = "arn:aws:states:::lambda:invoke"

                Parameters = {
                  FunctionName = aws_lambda_function.flush_elasticache.arn
                  Payload = {
                    "execution_arn.$"  = "$$.Execution.Id"
                    "execution_name.$" = "$$.Execution.Name"
                    "cluster_name"     = var.cluster_name
                  }
                }

                ResultPath = "$.elasticache_flush"
                Next       = "ElasticacheFlushedResult"
              }

              ElasticacheFlushedResult = {
                Type = "Pass"

                Parameters = {
                  service           = "elasticache"
                  action            = "flushed"
                  "lambda_result.$" = "$.elasticache_flush.Payload"
                }

                End = true
              }
            }
          }
        ]

        ResultPath = "$.hibernate_compute_results"
        Next       = "TerraformNetworkHibernate"
      }

      TerraformNetworkHibernate = {
        Type     = "Task"
        Resource = "arn:aws:states:::codebuild:startBuild.sync"

        Parameters = {
          ProjectName = aws_codebuild_project.hibernate_network.name

          EnvironmentVariablesOverride = [
            {
              Name  = "TF_ACTION"
              Value = "hibernate"
              Type  = "PLAINTEXT"
            },
            {
              Name  = "CLUSTER_NAME"
              Value = var.cluster_name
              Type  = "PLAINTEXT"
            },
            {
              Name  = "NATGW_AZS_JSON"
              Value = "[]"
              Type  = "PLAINTEXT"
            },
            {
              Name  = "VPC_ENDPOINTS_JSON"
              Value = "{}"
              Type  = "PLAINTEXT"
            }
          ]
        }

        ResultPath = "$.tofu_network_hibernate"
        Next       = "SendHibernateComplete"
      }

      SendHibernateComplete = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"

        Parameters = {
          FunctionName = aws_lambda_function.hibernate_complete.arn
          Payload = {
            "execution_arn.$"   = "$$.Execution.Id"
            "execution_name.$"  = "$$.Execution.Name"
            "started_at.$"      = "$$.Execution.StartTime"
            "cluster_name"      = var.cluster_name
            "compute_results.$" = "$.hibernate_compute_results"
            "network_result.$"  = "$.tofu_network_hibernate"
          }
        }

        ResultPath = "$.hibernate_complete"
        Next       = "HibernateDone"
      }

      HibernateDone = {
        Type = "Succeed"
      }
    }
  })
}

#########################
# Initial slack message #
#########################

data "archive_file" "hibernate_start" {
  type        = "zip"
  source_file = "${path.module}/lambda/hibernate_start/main.py"
  output_path = "${path.module}/lambda/hibernate_start/function.zip"
}

resource "aws_iam_role" "hive_hibernate_slackbot" {
  name = "${var.cluster_name}-hive-hibernate-slackbot"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

data "aws_iam_policy_document" "allow_access_secretmanager" {
  version = "2012-10-17"

  statement {
    sid    = "AllowAccessSecretsManager"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    resources = [
      aws_secretsmanager_secret.hive_hibernate.arn
    ]
  }
}

resource "aws_iam_role_policy" "allow_access_secretmanager" {
  name   = "${var.cluster_name}-allow-access-secretmanager"
  role   = aws_iam_role.hive_hibernate_slackbot.id
  policy = data.aws_iam_policy_document.allow_access_secretmanager.json
}

resource "aws_iam_role_policy_attachment" "start_lambda_basic_execution" {
  role       = aws_iam_role.hive_hibernate_slackbot.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "hibernate_start" {
  filename         = data.archive_file.hibernate_start.output_path
  function_name    = "${var.cluster_name}-hibernate-start"
  role             = aws_iam_role.hive_hibernate_slackbot.arn
  handler          = "main.lambda_handler"
  source_code_hash = data.archive_file.hibernate_start.output_base64sha256
  runtime          = "python3.12"

  environment {
    variables = {
      SECRET_NAME  = aws_secretsmanager_secret.hive_hibernate.name
      CLUSTER_NAME = module.eks_cluster.cluster_name
    }
  }
}

############################
# ElastiCache flush Lambda #
############################

data "archive_file" "flush_elasticache" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/flush_elasticache/package"
  output_path = "${path.module}/lambda/flush_elasticache/function.zip"
}

resource "aws_iam_role" "flush_elasticache" {
  name = "${var.cluster_name}-flush-elasticache"

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

resource "aws_iam_role_policy_attachment" "flush_elasticache_basic_execution" {
  role       = aws_iam_role.flush_elasticache.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "flush_elasticache" {
  filename         = data.archive_file.flush_elasticache.output_path
  function_name    = "${var.cluster_name}-flush-elasticache"
  role             = aws_iam_role.flush_elasticache.arn
  handler          = "main.lambda_handler"
  source_code_hash = data.archive_file.flush_elasticache.output_base64sha256
  runtime          = "python3.12"

  vpc_config {
    subnet_ids         = module.vpc.private_subnet_ids
    security_group_ids = [aws_security_group.flush_elasticache_lambda.id]
  }
  environment {
    variables = {
      CLUSTER_NAME         = module.eks_cluster.cluster_name
      ELASTICACHE_ENDPOINT = module.cache.address
      ELASTICACHE_PORT     = module.cache.cache_port
      ELASTICACHE_SSL      = "true"
      FLUSH_MODE           = "ASYNC"
    }
  }
}

## Security Groups for Lambda
resource "aws_iam_role_policy_attachment" "flush_elasticache_vpc_access" {
  role       = aws_iam_role.flush_elasticache.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_security_group" "flush_elasticache_lambda" {
  name        = "${var.cluster_name}-flush-elasticache-lambda"
  description = "Security group for Lambda flushing ElastiCache Serverless"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "${var.cluster_name}-flush-elasticache-lambda"
  }
}

resource "aws_security_group_rule" "flush_lambda_egress_to_elasticache" {
  type                     = "egress"
  description              = "Allow Lambda to access ElastiCache Redis/Valkey"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.flush_elasticache_lambda.id
  source_security_group_id = module.cache.cache_sg_id
}

resource "aws_security_group_rule" "allow_flush_lambda_to_elasticache" {
  type                     = "ingress"
  description              = "Allow flush Lambda to access ElastiCache"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = module.cache.cache_sg_id
  source_security_group_id = aws_security_group.flush_elasticache_lambda.id
}

#########################################################
# CodeBuild: Hibernate Networks (NATGW & VPC Endpoints) #
#########################################################
resource "aws_iam_role" "hibernate_network_codebuild" {
  name = "${var.cluster_name}-hibernate-network-codebuild"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_codebuild_project" "hibernate_network" {
  name         = "${var.cluster_name}-hibernate-network"
  service_role = aws_iam_role.hibernate_network_codebuild.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type      = "GITHUB"
    location  = var.terraform_repo_url
    buildspec = "environments/dev/infra/buildspecs/hibernate-network.yml"
  }

  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
    }
  }
}

data "aws_iam_policy_document" "hibernate_network_codebuild_permissions" {
  statement {
    sid    = "AllowTerraformStateAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]

    resources = [
      data.terraform_remote_state.shared.outputs.state_bucket_arn,
      "${data.terraform_remote_state.shared.outputs.state_bucket_arn}/*"
    ]
  }

  statement {
    sid    = "AllowNetworkHibernate"
    effect = "Allow"

    actions = [
      "ec2:Describe*",
      "ec2:CreateNatGateway",
      "ec2:DeleteNatGateway",
      "ec2:CreateVpcEndpoint",
      "ec2:DeleteVpcEndpoints",
      "ec2:ModifyVpcEndpoint",
      "ec2:CreateRoute",
      "ec2:ReplaceRoute",
      "ec2:DeleteRoute",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:ModifySubnetAttribute",
      "ec2:CreateTags",
      "ec2:DeleteTags"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowCodeBuildCloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.cluster_name}-hibernate-network",
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.cluster_name}-hibernate-network:*"
    ]
  }
}

resource "aws_iam_role_policy" "hibernate_network_codebuild_permissions" {
  name   = "${var.cluster_name}-hibernate-network-codebuild-permissions"
  role   = aws_iam_role.hibernate_network_codebuild.id
  policy = data.aws_iam_policy_document.hibernate_network_codebuild_permissions.json
}

############################
# Complete slack message   #
############################
data "archive_file" "hibernate_complete" {
  type        = "zip"
  source_file = "${path.module}/lambda/hibernate_complete/main.py"
  output_path = "${path.module}/lambda/hibernate_complete/function.zip"
}

resource "aws_lambda_function" "hibernate_complete" {
  filename         = data.archive_file.hibernate_complete.output_path
  function_name    = "${var.cluster_name}-hibernate-complete"
  role             = aws_iam_role.hive_hibernate_slackbot.arn
  handler          = "main.lambda_handler"
  source_code_hash = data.archive_file.hibernate_complete.output_base64sha256
  runtime          = "python3.12"

  environment {
    variables = {
      SECRET_NAME  = aws_secretsmanager_secret.hive_hibernate.name
      CLUSTER_NAME = module.eks_cluster.cluster_name
    }
  }
}
