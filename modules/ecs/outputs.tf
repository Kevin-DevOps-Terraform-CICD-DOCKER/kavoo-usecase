output "cluster_arn" {
  description = "ECS Cluster ARN"
  value       = local.cluster_arn
}

output "cluster_name" {
  description = "ECS Cluster name"
  value       = local.should_use_existing_cluster ? local.cluster_name : aws_ecs_cluster.main[0].name
}

output "execution_role_arn" {
  description = "ECS Execution Role ARN"
  value       = local.execution_role_arn
}

output "execution_role_name" {
  description = "ECS Execution Role name"
  value       = local.execution_role_name
}

output "resource_strategy_info" {
  description = "Information about resource usage strategy"
  value = {
    cluster_strategy          = local.should_use_existing_cluster ? "using-existing" : "creating-new"
    execution_role_strategy   = local.should_use_existing_execution_role ? "using-existing" : "creating-new"
    log_groups_strategy       = local.should_use_existing_log_groups
    services_strategy         = local.should_use_existing_services
    task_definitions_strategy = local.should_use_existing_task_definitions
  }
}

# Debug outputs para verificar estratégia de recursos
output "resource_strategy_debug" {
  description = "Debug completo da estratégia de recursos ECS"
  value = local.resource_strategy_debug
}
