data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  firehose_log_group_name  = "/aws/kinesisfirehose/${var.firehose_name}"
  firehose_log_stream_name = "S3Delivery"
}

data "aws_iam_policy_document" "firehose_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "firehose" {
  name               = "${var.firehose_name}-firehose-role"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json
}

data "aws_iam_policy_document" "firehose" {
  statement {
    sid    = "AllowS3Delivery"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject",
    ]
    resources = [
      var.bucket_arn,
      "${var.bucket_arn}/*",
    ]
  }

  statement {
    sid    = "AllowFirehoseLogging"
    effect = "Allow"
    actions = [
      "logs:PutLogEvents",
    ]
    resources = [
      aws_cloudwatch_log_group.firehose.arn,
      "${aws_cloudwatch_log_group.firehose.arn}:log-stream:${local.firehose_log_stream_name}",
    ]
  }
}

resource "aws_iam_role_policy" "firehose" {
  name   = "${var.firehose_name}-firehose-policy"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose.json
}

resource "aws_cloudwatch_log_group" "firehose" {
  name              = local.firehose_log_group_name
  retention_in_days = var.firehose_log_retention_in_days
}

resource "aws_cloudwatch_log_stream" "firehose" {
  name           = local.firehose_log_stream_name
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

resource "aws_kinesis_firehose_delivery_stream" "default" {
  name        = var.firehose_name
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose.arn
    bucket_arn          = var.bucket_arn
    prefix              = var.s3_prefix
    error_output_prefix = var.s3_error_output_prefix
    buffering_size      = var.buffering_size
    buffering_interval  = var.buffering_interval
    compression_format  = var.compression_format

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose.name
    }
  }
}

data "aws_iam_policy_document" "logs_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]

    condition {
      test     = "StringLike"
      variable = "aws:SourceArn"
      values = [
        "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*",
      ]
    }
  }
}

resource "aws_iam_role" "logs_to_firehose" {
  name               = "${var.firehose_name}-logs-to-firehose-role"
  assume_role_policy = data.aws_iam_policy_document.logs_assume_role.json
}

data "aws_iam_policy_document" "logs_to_firehose" {
  statement {
    sid    = "AllowPutToFirehose"
    effect = "Allow"
    actions = [
      "firehose:PutRecord",
      "firehose:PutRecordBatch",
    ]
    resources = [aws_kinesis_firehose_delivery_stream.default.arn]
  }
}

resource "aws_iam_role_policy" "logs_to_firehose" {
  name   = "${var.firehose_name}-logs-to-firehose-policy"
  role   = aws_iam_role.logs_to_firehose.id
  policy = data.aws_iam_policy_document.logs_to_firehose.json
}

resource "aws_cloudwatch_log_subscription_filter" "default" {
  for_each = var.log_groups

  name            = each.value.subscription_filter_name
  role_arn        = aws_iam_role.logs_to_firehose.arn
  destination_arn = aws_kinesis_firehose_delivery_stream.default.arn
  log_group_name  = each.value.log_group_name
  filter_pattern  = each.value.filter_pattern
}
