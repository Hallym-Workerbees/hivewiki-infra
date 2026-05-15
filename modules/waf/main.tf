resource "aws_wafv2_web_acl" "alb" {
  name        = "${var.cluster_name}-web-acl"
  description = "WAF of ${var.cluster_name}"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit-all-ip"
    priority = 0

    dynamic "action" {
      for_each = var.waf_rule_action == "count" ? [1] : []

      content {
        count {}
      }
    }

    dynamic "action" {
      for_each = var.waf_rule_action == "block" ? [1] : []

      content {
        block {}
      }
    }

    statement {
      rate_based_statement {
        limit                 = var.rate_limit
        aggregate_key_type    = "IP"
        evaluation_window_sec = var.rate_limit_eval_window
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-app-ip"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesAmazonIpReputationList"
    priority = 10

    dynamic "override_action" {
      for_each = var.waf_rule_action == "count" ? [1] : []

      content {
        count {}
      }
    }

    dynamic "override_action" {
      for_each = var.waf_rule_action == "block" ? [1] : []

      content {
        none {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesAmazonIpReputationList"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    dynamic "override_action" {
      for_each = var.waf_rule_action == "count" ? [1] : []

      content {
        count {}
      }
    }

    dynamic "override_action" {
      for_each = var.waf_rule_action == "block" ? [1] : []

      content {
        none {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesSQLiRuleSet"
    priority = 30

    dynamic "override_action" {
      for_each = var.waf_rule_action == "count" ? [1] : []

      content {
        count {}
      }
    }

    dynamic "override_action" {
      for_each = var.waf_rule_action == "block" ? [1] : []

      content {
        none {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesSQLiRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 40

    dynamic "override_action" {
      for_each = var.waf_rule_action == "count" ? [1] : []

      content {
        count {}
      }
    }

    dynamic "override_action" {
      for_each = var.waf_rule_action == "block" ? [1] : []

      content {
        none {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.cluster_name}-alb-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "alb" {
  count = length(var.log_destination_configs) > 0 ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.alb.arn
  log_destination_configs = var.log_destination_configs

  dynamic "redacted_fields" {
    for_each = var.redacted_single_headers

    content {
      single_header {
        name = redacted_fields.value
      }
    }
  }
}
