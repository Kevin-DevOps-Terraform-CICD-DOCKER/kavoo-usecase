output "budget_name" {
  description = "Name of the budget"
  value       = var.existing_resources.budget_exists ? data.aws_budgets_budget.existing[0].name : aws_budgets_budget.monthly_budget[0].name
}

output "budget_arn" {
  description = "ARN of the budget"
  value       = var.existing_resources.budget_exists ? null : aws_budgets_budget.monthly_budget[0].arn
}

output "budget_id" {
  description = "ID of the budget"
  value       = var.existing_resources.budget_exists ? data.aws_budgets_budget.existing[0].name : aws_budgets_budget.monthly_budget[0].id
}

output "dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = var.existing_resources.dashboard_exists ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${var.project_name}-cost-monitoring" : "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.cost_monitoring[0].dashboard_name}"
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.existing_resources.dashboard_exists ? "${var.project_name}-cost-monitoring" : aws_cloudwatch_dashboard.cost_monitoring[0].dashboard_name
}

output "billing_alarm_arn" {
  description = "ARN of the billing alarm"
  value       = var.existing_resources.alarm_exists ? null : aws_cloudwatch_metric_alarm.high_estimated_charges[0].arn
}

output "monitoring_resources" {
  description = "All monitoring resources information"
  value = {
    budget_name           = var.existing_resources.budget_exists ? data.aws_budgets_budget.existing[0].name : aws_budgets_budget.monthly_budget[0].name
    dashboard_name        = var.existing_resources.dashboard_exists ? "${var.project_name}-cost-monitoring" : aws_cloudwatch_dashboard.cost_monitoring[0].dashboard_name
    billing_alarm_name    = var.existing_resources.alarm_exists ? "${var.project_name}-high-estimated-charges" : aws_cloudwatch_metric_alarm.high_estimated_charges[0].alarm_name
  }
}