data "aws_caller_identity" "current" {}

locals {
  rds_db_identifier  = var.rds_db_identifier
  lambda_root        = "${path.module}/lambda"
  lambda_build_root  = "${path.module}/build/lambda"
  live_vpc_state_key = "live/cluster/vpc/terraform.tfstate"
}

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

    resources = [var.ng_arn]
  }

  statement {
    sid    = "AllowCheckEC2"
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances"
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
            StartAt = "CheckRdsInitialStatus"

            States = {
              CheckRdsInitialStatus = {
                Type     = "Task"
                Resource = "arn:aws:states:::aws-sdk:rds:describeDBInstances"

                Parameters = {
                  DbInstanceIdentifier = local.rds_db_identifier
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
                  DbInstanceIdentifier = local.rds_db_identifier
                }

                ResultPath = "$.rdsStop"
                Next       = "CheckRdsStatus"
              }

              CheckRdsStatus = {
                Type     = "Task"
                Resource = "arn:aws:states:::aws-sdk:rds:describeDBInstances"

                Parameters = {
                  DbInstanceIdentifier = local.rds_db_identifier
                }

                ResultPath = "$.rdsStatus"
                Next       = "CheckRdsStopped"
              }

              CheckRdsStopped = {
                Type = "Choice"

                Choices = [
                  {
                    Variable     = "$.rdsStatus.DbInstances[0].DbInstanceStatus"
                    StringEquals = "stopped"
                    Next         = "RdsStoppedResult"
                  }
                ]
                Default = "WaitBeforeCheckingRdsStopped"
              }

              WaitBeforeCheckingRdsStopped = {
                Type    = "Wait"
                Seconds = var.hibernate_db_instance_polling_period_seconds
                Next    = "CheckRdsStatus"
              }

              RdsStoppedResult = {
                Type = "Pass"

                Parameters = {
                  service                = "rds"
                  action                 = "stopped"
                  db_instance_identifier = local.rds_db_identifier
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
                  db_instance_identifier = local.rds_db_identifier
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
                  ClusterName   = var.eks_cluster_name
                  NodegroupName = var.ng_name
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
                  ClusterName   = var.eks_cluster_name
                  NodegroupName = var.ng_name

                  ScalingConfig = {
                    MinSize     = 0
                    DesiredSize = 0
                  }
                }

                ResultPath = "$.eks_scale_down"
                Next       = "ListNodeGroupInstances"
              }

              ListNodeGroupInstances = {
                Type     = "Task"
                Resource = "arn:aws:states:::aws-sdk:ec2:describeInstances"

                Parameters = {
                  Filters = [
                    {
                      Name = "tag:eks:cluster-name",
                      Values = [
                        var.eks_cluster_name
                      ]
                    },
                    {
                      Name = "tag:eks:nodegroup-name",
                      Values = [
                        var.ng_name
                      ]
                    },
                    {
                      Name = "instance-state-name",
                      Values = [
                        "pending",
                        "running",
                        "stopping",
                        "stopped",
                        "shutting-down"
                      ]
                    }
                  ]
                }
                ResultSelector = {
                  "instanceIds.$" = "$.Reservations[*].Instances[*].InstanceId"
                }
                ResultPath = "$.instanceCheck"
                Next       = "CountRemainingInstances"
              }

              CountRemainingInstances = {
                Type = "Pass"
                Parameters = {
                  "remainingInstanceCount.$" : "States.ArrayLength($.instanceCheck.instanceIds)",
                  "instanceIds.$" : "$.instanceCheck.instanceIds"
                }
                ResultPath = "$.instanceCheck"
                Next       = "CheckInstancesGone"
              }

              CheckInstancesGone = {
                Type = "Choice"
                Choices = [
                  {
                    Variable      = "$.instanceCheck.remainingInstanceCount"
                    NumericEquals = 0
                    Next          = "EksScaledDownResult"
                  }
                ]
                Default = "WaitBeforeCheckingNodeGroupScaledDown"
              }

              WaitBeforeCheckingNodeGroupScaledDown = {
                Type    = "Wait"
                Seconds = var.hibernate_ng_polling_period_seconds
                Next    = "ListNodeGroupInstances"
              }

              EksScaledDownResult = {
                Type = "Pass"

                Parameters = {
                  service              = "eks"
                  action               = "scaled_down"
                  cluster_name         = var.eks_cluster_name
                  nodegroup_name       = var.ng_name
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
                  cluster_name         = var.eks_cluster_name
                  nodegroup_name       = var.ng_name
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
              Name  = "ENABLE_VPCE_JSON"
              Value = "false"
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

data "aws_iam_policy_document" "hibernate_sched" {
  statement {
    effect = "Allow"
    actions = [
      "states:StartExecution"
    ]
    resources = [
      aws_sfn_state_machine.hibernate.arn
    ]
  }
}

resource "aws_iam_role" "hibernate_sched" {
  name = "${var.cluster_name}-hibernate-sched"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "scheduler.amazonaws.com"
        },
        Action = [
          "sts:AssumeRole"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "hibernate_sched" {
  name   = "${var.cluster_name}-hibernate-sched"
  role   = aws_iam_role.hibernate_sched.id
  policy = data.aws_iam_policy_document.hibernate_sched.json
}

resource "aws_scheduler_schedule" "hibernate_sched" {
  name = "${var.cluster_name}-hibernate-schedule"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression_timezone = "Asia/Seoul"
  schedule_expression          = "cron(${var.hibernate_sched_cron})"

  target {
    arn      = aws_sfn_state_machine.hibernate.arn
    role_arn = aws_iam_role.hibernate_sched.arn
    input    = jsonencode({})
  }
}

#########################
# Initial slack message #
#########################

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
  filename         = "${local.lambda_build_root}/hibernate_start/function.zip"
  function_name    = "${var.cluster_name}-hibernate-start"
  role             = aws_iam_role.hive_hibernate_slackbot.arn
  handler          = "main.lambda_handler"
  source_code_hash = filebase64sha256("${local.lambda_build_root}/hibernate_start/function.zip")
  runtime          = "python3.12"

  environment {
    variables = {
      SECRET_NAME  = aws_secretsmanager_secret.hive_hibernate.name
      CLUSTER_NAME = var.eks_cluster_name
    }
  }
}

##############################
# ElastiCache - flush Lambda #
##############################

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
  filename         = "${local.lambda_build_root}/flush_elasticache/function.zip"
  function_name    = "${var.cluster_name}-flush-elasticache"
  role             = aws_iam_role.flush_elasticache.arn
  handler          = "main.lambda_handler"
  source_code_hash = filebase64sha256("${local.lambda_build_root}/flush_elasticache/function.zip")
  runtime          = "python3.12"

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.flush_elasticache_lambda.id]
  }
  environment {
    variables = {
      CLUSTER_NAME         = var.eks_cluster_name
      ELASTICACHE_ENDPOINT = var.cache_address
      ELASTICACHE_PORT     = var.cache_port
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
  vpc_id      = var.vpc_id

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
  source_security_group_id = var.cache_sg_id
}

resource "aws_security_group_rule" "allow_flush_lambda_to_elasticache" {
  type                     = "ingress"
  description              = "Allow flush Lambda to access ElastiCache"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = var.cache_sg_id
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
    buildspec = "live/cluster/vpc/buildspecs/hibernate-network.yml"
  }

  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
    }
  }
}

data "aws_iam_policy_document" "hibernate_network_codebuild_permissions" {
  statement {
    sid    = "AllowTerraformStateBucketMetadataRead"
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning",
      "s3:GetEncryptionConfiguration"
    ]

    resources = [var.state_bucket_arn]
  }

  statement {
    sid    = "AllowTerraformStateBucketList"
    effect = "Allow"

    actions = [
      "s3:ListBucket"
    ]

    resources = [var.state_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        local.live_vpc_state_key,
        "${local.live_vpc_state_key}.tflock"
      ]
    }
  }

  statement {
    sid    = "AllowTerraformVpcStateObjectAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [
      "${var.state_bucket_arn}/${local.live_vpc_state_key}",
      "${var.state_bucket_arn}/${local.live_vpc_state_key}.tflock"
    ]
  }

  statement {
    sid    = "AllowNetworkHibernate"
    effect = "Allow"

    actions = [
      "ec2:Describe*",
      "ec2:AllocateAddress",
      "ec2:AssociateAddress",
      "ec2:CreateNatGateway",
      "ec2:DeleteNatGateway",
      "ec2:CreateVpcEndpoint",
      "ec2:DeleteVpcEndpoints",
      "ec2:ModifyVpcEndpoint",
      "ec2:CreateRoute",
      "ec2:ReplaceRoute",
      "ec2:DeleteRoute",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateAddress",
      "ec2:DisassociateRouteTable",
      "ec2:ModifySubnetAttribute",
      "ec2:ReleaseAddress",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:DescribeSecurityGroups",
      "ec2:DeleteSecurityGroup",
      "ec2:RevokeSecurityGroupIngress",
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
resource "aws_lambda_function" "hibernate_complete" {
  filename         = "${local.lambda_build_root}/hibernate_complete/function.zip"
  function_name    = "${var.cluster_name}-hibernate-complete"
  role             = aws_iam_role.hive_hibernate_slackbot.arn
  handler          = "main.lambda_handler"
  source_code_hash = filebase64sha256("${local.lambda_build_root}/hibernate_complete/function.zip")
  runtime          = "python3.12"

  environment {
    variables = {
      SECRET_NAME  = aws_secretsmanager_secret.hive_hibernate.name
      CLUSTER_NAME = var.eks_cluster_name
    }
  }
}

##########
# Reboot #
##########
resource "aws_iam_role" "reboot" {
  name = "${var.cluster_name}-reboot"

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

data "aws_iam_policy_document" "reboot_permissions" {
  statement {
    sid    = "AllowRebootStartLambdaInvoke"
    effect = "Allow"

    actions = [
      "lambda:InvokeFunction"
    ]

    resources = [
      aws_lambda_function.reboot_start.arn,
      aws_lambda_function.reboot_complete.arn
    ]
  }

  statement {
    sid    = "AllowRdsRestart"
    effect = "Allow"

    actions = [
      "rds:StartDBInstance",
      "rds:DescribeDBInstances"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowEksScaleUp"
    effect = "Allow"

    actions = [
      "eks:DescribeNodegroup",
      "eks:UpdateNodegroupConfig"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowCheckRebootEC2"
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowNetworkRebootCodeBuild"
    effect = "Allow"

    actions = [
      "codebuild:StartBuild",
      "codebuild:BatchGetBuilds",
      "codebuild:StopBuild"
    ]

    resources = [
      aws_codebuild_project.reboot_network.arn
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

resource "aws_iam_role_policy" "reboot_permissions" {
  name   = "${var.cluster_name}-reboot-permissions"
  role   = aws_iam_role.reboot.id
  policy = data.aws_iam_policy_document.reboot_permissions.json
}


resource "aws_sfn_state_machine" "reboot" {
  name     = "${var.cluster_name}-reboot"
  role_arn = aws_iam_role.reboot.arn

  definition = jsonencode({
    Comment = "${var.cluster_name} Cloud resource recovery after off-hours"
    StartAt = "SendRebootStart"

    States = {
      SendRebootStart = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"

        Parameters = {
          FunctionName = aws_lambda_function.reboot_start.arn
          Payload = {
            "execution_arn.$"  = "$$.Execution.Id"
            "execution_name.$" = "$$.Execution.Name"
            "started_at.$"     = "$$.Execution.StartTime"
            "cluster_name"     = var.cluster_name
          }
        }

        ResultPath = "$.reboot_start"
        Next       = "TerraformNetworkReboot"
      }

      TerraformNetworkReboot = {
        Type     = "Task"
        Resource = "arn:aws:states:::codebuild:startBuild.sync"

        Parameters = {
          ProjectName = aws_codebuild_project.reboot_network.name
        }

        ResultPath = "$.tofu_network_reboot"
        Next       = "RebootComputes"
      }

      RebootComputes = {
        Type = "Parallel"

        Branches = [
          {
            StartAt = "CheckRdsStatus"

            States = {
              CheckRdsStatus = {
                Type     = "Task"
                Resource = "arn:aws:states:::aws-sdk:rds:describeDBInstances"

                Parameters = {
                  DbInstanceIdentifier = local.rds_db_identifier
                }

                ResultPath = "$.rds_describe"
                Next       = "ShouldStartRds"
              }

              ShouldStartRds = {
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
                        StringEquals = "stopped"
                      }
                    ]
                    Next = "StartRds"
                  }
                ]

                Default = "SkipRds"
              }

              StartRds = {
                Type     = "Task"
                Resource = "arn:aws:states:::aws-sdk:rds:startDBInstance"

                Parameters = {
                  DbInstanceIdentifier = local.rds_db_identifier
                }

                ResultPath = "$.rds_reboot"
                Next       = "CheckRdsAvailableStatus"
              }

              CheckRdsAvailableStatus = {
                Type     = "Task"
                Resource = "arn:aws:states:::aws-sdk:rds:describeDBInstances"

                Parameters = {
                  DbInstanceIdentifier = local.rds_db_identifier
                }

                ResultPath = "$.rds_status"
                Next       = "CheckRdsAvailable"
              }

              CheckRdsAvailable = {
                Type = "Choice"

                Choices = [
                  {
                    Variable     = "$.rds_status.DbInstances[0].DbInstanceStatus"
                    StringEquals = "available"
                    Next         = "RdsRestartedResult"
                  }
                ]

                Default = "WaitBeforeCheckingRdsAvailable"
              }

              WaitBeforeCheckingRdsAvailable = {
                Type    = "Wait"
                Seconds = var.reboot_db_instance_polling_period_seconds
                Next    = "CheckRdsAvailableStatus"
              }

              RdsRestartedResult = {
                Type = "Pass"

                Parameters = {
                  service                = "rds"
                  action                 = "started"
                  db_instance_identifier = local.rds_db_identifier
                  "previous_status.$"    = "$.rds_describe.DbInstances[0].DbInstanceStatus"
                }

                End = true
              }

              SkipRds = {
                Type = "Pass"

                Parameters = {
                  service                = "rds"
                  action                 = "skipped"
                  reason                 = "RDS is not stopped"
                  db_instance_identifier = local.rds_db_identifier
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
                  ClusterName   = var.eks_cluster_name
                  NodegroupName = var.ng_name
                }

                ResultPath = "$.eks_nodegroup"
                Next       = "ShouldScaleUpEks"
              }

              ShouldScaleUpEks = {
                Type = "Choice"
                Choices = [
                  {
                    And = [
                      {
                        Variable  = "$.eks_nodegroup.Nodegroup.ScalingConfig.DesiredSize"
                        IsPresent = true
                      },
                      {
                        Variable      = "$.eks_nodegroup.Nodegroup.ScalingConfig.DesiredSize"
                        NumericEquals = 0
                      }
                    ]
                    Next = "ScaleUpEks"
                  }
                ]
                Default = "SkipEks"
              }

              ScaleUpEks = {
                Type     = "Task"
                Resource = "arn:aws:states:::aws-sdk:eks:updateNodegroupConfig"

                Parameters = {
                  ClusterName   = var.eks_cluster_name
                  NodegroupName = var.ng_name

                  ScalingConfig = {
                    MinSize     = var.eks_node_group_min_size
                    DesiredSize = var.eks_node_group_desired_size
                    MaxSize     = var.eks_node_group_max_size
                  }
                }

                ResultPath = "$.eks_scale_up"
                Next       = "ListRunningNodeGroupInstances"
              }

              ListRunningNodeGroupInstances = {
                Type     = "Task"
                Resource = "arn:aws:states:::aws-sdk:ec2:describeInstances"

                Parameters = {
                  Filters = [
                    {
                      Name = "tag:eks:cluster-name"
                      Values = [
                        var.eks_cluster_name
                      ]
                    },
                    {
                      Name = "tag:eks:nodegroup-name"
                      Values = [
                        var.ng_name
                      ]
                    },
                    {
                      Name = "instance-state-name"
                      Values = [
                        "running"
                      ]
                    }
                  ]
                }

                ResultSelector = {
                  "instanceIds.$" = "$.Reservations[*].Instances[*].InstanceId"
                }

                ResultPath = "$.running_instance_check"
                Next       = "CountRunningNodeGroupInstances"
              }

              CountRunningNodeGroupInstances = {
                Type = "Pass"

                Parameters = {
                  "runningInstanceCount.$" = "States.ArrayLength($.running_instance_check.instanceIds)"
                  "instanceIds.$"          = "$.running_instance_check.instanceIds"
                  targetDesired            = var.eks_node_group_desired_size
                }

                ResultPath = "$.running_instance_check"
                Next       = "CheckRunningNodeGroupInstances"
              }

              CheckRunningNodeGroupInstances = {
                Type = "Choice"

                Choices = [
                  {
                    Variable      = "$.running_instance_check.runningInstanceCount"
                    NumericEquals = var.eks_node_group_desired_size
                    Next          = "WaitAfterNodeGroupRunning"
                  }
                ]

                Default = "WaitBeforeCheckingRunningNodeGroupInstances"
              }

              WaitBeforeCheckingRunningNodeGroupInstances = {
                Type    = "Wait"
                Seconds = var.reboot_ng_polling_period_seconds
                Next    = "ListRunningNodeGroupInstances"
              }

              WaitAfterNodeGroupRunning = {
                Type    = "Wait"
                Seconds = var.reboot_ng_post_scale_up_wait_seconds
                Next    = "EksScaledUpResult"
              }

              EksScaledUpResult = {
                Type = "Pass"

                Parameters = {
                  service              = "eks"
                  action               = "scaled_up"
                  cluster_name         = var.eks_cluster_name
                  nodegroup_name       = var.ng_name
                  "previous_min.$"     = "$.eks_nodegroup.Nodegroup.ScalingConfig.MinSize"
                  "previous_desired.$" = "$.eks_nodegroup.Nodegroup.ScalingConfig.DesiredSize"
                  "previous_max.$"     = "$.eks_nodegroup.Nodegroup.ScalingConfig.MaxSize"
                  target_min           = var.eks_node_group_min_size
                  target_desired       = var.eks_node_group_desired_size
                  target_max           = var.eks_node_group_max_size
                }

                End = true
              }

              SkipEks = {
                Type = "Pass"

                Parameters = {
                  service              = "eks"
                  action               = "skipped"
                  reason               = "EKS nodegroup desired size is already non-zero"
                  cluster_name         = var.eks_cluster_name
                  nodegroup_name       = var.ng_name
                  "previous_min.$"     = "$.eks_nodegroup.Nodegroup.ScalingConfig.MinSize"
                  "previous_desired.$" = "$.eks_nodegroup.Nodegroup.ScalingConfig.DesiredSize"
                  "previous_max.$"     = "$.eks_nodegroup.Nodegroup.ScalingConfig.MaxSize"
                }

                End = true
              }
            }
          }
        ]

        ResultPath = "$.reboot_compute_results"
        Next       = "SendRebootComplete"
      }

      SendRebootComplete = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"

        Parameters = {
          FunctionName = aws_lambda_function.reboot_complete.arn
          Payload = {
            "execution_arn.$"   = "$$.Execution.Id"
            "execution_name.$"  = "$$.Execution.Name"
            "started_at.$"      = "$$.Execution.StartTime"
            "cluster_name"      = var.cluster_name
            "compute_results.$" = "$.reboot_compute_results"
            "network_result.$"  = "$.tofu_network_reboot"
          }
        }

        ResultPath = "$.reboot_complete"
        Next       = "RebootDone"
      }

      RebootDone = {
        Type = "Succeed"
      }
    }
  })
}

data "aws_iam_policy_document" "reboot_sched" {
  statement {
    effect = "Allow"
    actions = [
      "states:StartExecution"
    ]
    resources = [
      aws_sfn_state_machine.reboot.arn
    ]
  }
}

resource "aws_iam_role" "reboot_sched" {
  name = "${var.cluster_name}-reboot-sched"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "scheduler.amazonaws.com"
        },
        Action = [
          "sts:AssumeRole"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "reboot_sched" {
  name   = "${var.cluster_name}-reboot-sched"
  role   = aws_iam_role.reboot_sched.id
  policy = data.aws_iam_policy_document.reboot_sched.json
}

resource "aws_scheduler_schedule" "reboot_sched" {
  name = "${var.cluster_name}-reboot-schedule"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression_timezone = "Asia/Seoul"
  schedule_expression          = "cron(${var.reboot_sched_cron})"

  target {
    arn      = aws_sfn_state_machine.reboot.arn
    role_arn = aws_iam_role.reboot_sched.arn
    input    = jsonencode({})
  }
}

resource "aws_lambda_function" "reboot_start" {
  filename         = "${local.lambda_build_root}/reboot_start/function.zip"
  function_name    = "${var.cluster_name}-reboot-start"
  role             = aws_iam_role.hive_hibernate_slackbot.arn
  handler          = "main.lambda_handler"
  source_code_hash = filebase64sha256("${local.lambda_build_root}/reboot_start/function.zip")
  runtime          = "python3.12"

  environment {
    variables = {
      SECRET_NAME  = aws_secretsmanager_secret.hive_hibernate.name
      CLUSTER_NAME = var.eks_cluster_name
    }
  }
}

resource "aws_iam_role" "reboot_network_codebuild" {
  name = "${var.cluster_name}-reboot-network-codebuild"

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

resource "aws_codebuild_project" "reboot_network" {
  name         = "${var.cluster_name}-reboot-network"
  service_role = aws_iam_role.reboot_network_codebuild.arn

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
    buildspec = "live/cluster/vpc/buildspecs/reboot-network.yml"
  }

  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
    }
  }
}

data "aws_iam_policy_document" "reboot_network_codebuild_permissions" {
  statement {
    sid    = "AllowTerraformStateBucketMetadataRead"
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning",
      "s3:GetEncryptionConfiguration"
    ]

    resources = [var.state_bucket_arn]
  }

  statement {
    sid    = "AllowTerraformStateBucketList"
    effect = "Allow"

    actions = [
      "s3:ListBucket"
    ]

    resources = [var.state_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        local.live_vpc_state_key,
        "${local.live_vpc_state_key}.tflock"
      ]
    }
  }

  statement {
    sid    = "AllowTerraformVpcStateObjectAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [
      "${var.state_bucket_arn}/${local.live_vpc_state_key}",
      "${var.state_bucket_arn}/${local.live_vpc_state_key}.tflock"
    ]
  }

  statement {
    sid    = "AllowNetworkReboot"
    effect = "Allow"

    actions = [
      "ec2:Describe*",
      "ec2:AllocateAddress",
      "ec2:AssociateAddress",
      "ec2:CreateNatGateway",
      "ec2:DeleteNatGateway",
      "ec2:CreateVpcEndpoint",
      "ec2:DeleteVpcEndpoints",
      "ec2:ModifyVpcEndpoint",
      "ec2:CreateRoute",
      "ec2:ReplaceRoute",
      "ec2:DeleteRoute",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateAddress",
      "ec2:DisassociateRouteTable",
      "ec2:ModifySubnetAttribute",
      "ec2:ReleaseAddress",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:DeleteSecurityGroup",
      "ec2:DescribeSecurityGroups",
      "ec2:CreateSecurityGroup",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress"
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
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.cluster_name}-reboot-network",
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.cluster_name}-reboot-network:*"
    ]
  }
}

resource "aws_iam_role_policy" "reboot_network_codebuild_permissions" {
  name   = "${var.cluster_name}-reboot-network-codebuild-permissions"
  role   = aws_iam_role.reboot_network_codebuild.id
  policy = data.aws_iam_policy_document.reboot_network_codebuild_permissions.json
}

resource "aws_lambda_function" "reboot_complete" {
  filename         = "${local.lambda_build_root}/reboot_complete/function.zip"
  function_name    = "${var.cluster_name}-reboot-complete"
  role             = aws_iam_role.hive_hibernate_slackbot.arn
  handler          = "main.lambda_handler"
  source_code_hash = filebase64sha256("${local.lambda_build_root}/reboot_complete/function.zip")
  runtime          = "python3.12"

  environment {
    variables = {
      SECRET_NAME  = aws_secretsmanager_secret.hive_hibernate.name
      CLUSTER_NAME = var.eks_cluster_name
    }
  }
}
