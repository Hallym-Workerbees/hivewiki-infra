data "aws_caller_identity" "current" {}

####################
# S3 (ALB Logging) #
####################
data "aws_iam_policy_document" "alb_logging" {
  statement {
    sid    = "AllowALBLogDelivery"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.cluster_name}-alb-gw-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
  }
}

module "alb_logging" {
  source             = "../../s3-archive"
  bucket_name        = "${var.cluster_name}-alb-gw-logs"
  bucket_policy_json = data.aws_iam_policy_document.alb_logging.json
  bucket_lifecycle_rules = {
    daily = {
      enabled         = true
      id              = "daily-backup-retention"
      prefix          = ""
      transitions     = []
      expiration_days = var.log_retention_in_days
    }
  }
}

#######
# WAF #
#######
module "waf_logging" {
  source      = "../../s3-archive"
  bucket_name = "aws-waf-logs-${var.cluster_name}"
  bucket_lifecycle_rules = {
    daily = {
      enabled         = true
      id              = "waf-log-retention"
      prefix          = ""
      transitions     = []
      expiration_days = var.log_retention_in_days
    }
  }
}

module "waf" {
  source                  = "../../waf"
  cluster_name            = var.cluster_name
  rate_limit              = var.waf_rate_limit
  rate_limit_eval_window  = 300
  waf_rule_action         = var.waf_rule_action
  log_destination_configs = [module.waf_logging.bucket_arn]
}
