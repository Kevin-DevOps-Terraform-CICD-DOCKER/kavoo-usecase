output "alb_arn" {
  description = "ALB ARN"
  value       = local.alb_arn
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = local.alb_dns_name
}

output "alb_zone_id" {
  description = "ALB zone ID"
  value       = local.alb_zone_id
}

output "frontend_target_group_arn" {
  description = "Frontend target group ARN"
  value = local.should_create_frontend_tg ? aws_lb_target_group.frontend[0].arn : (
    local.frontend_tg_exists ? data.aws_lb_target_group.existing_frontend[0].arn : null
  )
}

output "target_group_arns" {
  description = "Map of target group ARNs by service name"
  value = merge(
    local.frontend_tg_exists || local.should_create_frontend_tg ? {
      frontend = local.should_create_frontend_tg ? aws_lb_target_group.frontend[0].arn : data.aws_lb_target_group.existing_frontend[0].arn
    } : {},
    {
      for api in var.api_services : api => (
        var.create_target_groups ? (
          contains(keys(aws_lb_target_group.apis), api) ? aws_lb_target_group.apis[api].arn : null
        ) : (
          contains(keys(data.aws_lb_target_group.existing_apis), api) ? data.aws_lb_target_group.existing_apis[api].arn : null
        )
      )
    }
  )
}

output "http_listener_arn" {
  description = "HTTP listener ARN"
  value       = local.http_listener_arn
}

output "https_listener_arn" {
  description = "HTTPS listener ARN (if certificate provided)"
  value       = var.certificate_arn != "" ? local.https_listener_arn : null
}

output "primary_listener" {
  description = "Primary listener reference for ECS dependency"
  value = local.should_create_listeners ? (
    var.certificate_arn != "" ? aws_lb_listener.https[0] : aws_lb_listener.main[0]
  ) : (
    var.certificate_arn != "" ? data.aws_lb_listener.existing_https[0] : data.aws_lb_listener.existing_http[0]
  )
}

output "listener_arn" {
  description = "Primary listener ARN"
  value       = local.primary_listener_arn
}

output "listener_rules_created" {
  description = "Map of created listener rules ARNs by service name"
  value       = var.create_listener_rules ? { for k, v in aws_lb_listener_rule.api_routing : k => v.arn } : {}
}

output "resource_creation_status" {
  description = "Status of resource creation"
  value = {
    load_balancer_created    = var.create_load_balancer
    target_groups_created    = var.create_target_groups  
    listener_rules_created   = var.create_listener_rules
    using_existing_alb       = !var.create_load_balancer
    using_existing_tgs       = !var.create_target_groups
    using_existing_rules     = !var.create_listener_rules
  }
}

output "target_groups_discovery_info" {
  description = "Information about automatic target groups discovery"
  value = var.create_target_groups ? null : {
    frontend_tg_exists = local.frontend_tg_exists
    api_target_groups_exist = local.api_target_groups_exist
    existing_api_tg_set = local.existing_api_tg_set
    discovery_method = "automatic_target_group_detection"
    lb_resources_check_result = local.lb_resources_check_result
  }
}