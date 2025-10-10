terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_budgets_budget" "monthly_budget" {
  count = var.existing_resources.budget_exists ? 0 : 1
  
  name         = "kavoo-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = var.budget_alert_threshold_1
    threshold_type            = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.alert_email_addresses
  }

  notification {
    comparison_operator        = "GREATER_THAN" 
    threshold                 = var.budget_alert_threshold_2
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.alert_email_addresses
  }

  tags = {
    Name        = "${var.project_name}-budget"
    Environment = var.environment
  }
}

data "aws_budgets_budget" "existing" {
  count       = var.existing_resources.budget_exists ? 1 : 0
  name        = "kavoo-monthly-budget"
  account_id  = data.aws_caller_identity.current.account_id
}

resource "aws_cloudwatch_dashboard" "cost_monitoring" {
  count          = var.existing_resources.dashboard_exists ? 0 : 1
  dashboard_name = "${var.project_name}-cost-monitoring"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Billing", "EstimatedCharges", "Currency", "USD"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          period  = 86400
          stat    = "Maximum"
          title   = "Estimated Monthly Charges ($)"
        }
      }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "high_estimated_charges" {
  count               = var.existing_resources.alarm_exists ? 0 : 1
  alarm_name          = "${var.project_name}-high-estimated-charges"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "86400"
  statistic           = "Maximum"
  threshold           = tonumber(var.monthly_budget_limit)
  alarm_description   = "Alert when estimated charges exceed ${var.monthly_budget_limit} USD"

  dimensions = {
    Currency = "USD"
  }

  tags = {
    Name        = "${var.project_name}-billing-alarm"
    Environment = var.environment
  }
}