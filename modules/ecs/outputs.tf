# Fornece ARN do cluster ECS para outros módulos
# Função: Permitir que outros recursos referenciem o cluster ECS
# Usa: local.cluster_arn (que pode ser de recurso existente ou novo)
# Usado por: outros módulos que precisam referenciar o cluster
output "cluster_arn" {
  description = "ECS Cluster ARN"
  value       = local.cluster_arn
}

# Fornece nome do cluster ECS para referência
# Função: Permitir que outros recursos identifiquem o cluster pelo nome
# Usa: local.should_use_existing_cluster, local.cluster_name, aws_ecs_cluster.main
# Usado por: scripts ou outros recursos que precisam do nome do cluster
output "cluster_name" {
  description = "ECS Cluster name"
  value       = local.should_use_existing_cluster ? local.cluster_name : aws_ecs_cluster.main[0].name
}

# Fornece ARN do execution role ECS para outros recursos
# Função: Permitir que task definitions referenciem o role de execução
# Usa: local.execution_role_arn (que pode ser de role existente ou novo)
# Usado por: outros módulos que criam task definitions ECS
output "execution_role_arn" {
  description = "ECS Execution Role ARN"
  value       = local.execution_role_arn
}

# Fornece nome do execution role ECS para políticas IAM
# Função: Permitir anexar políticas adicionais ao role de execução
# Usa: local.execution_role_name (que pode ser de role existente ou novo)
# Usado por: recursos que precisam anexar políticas ao execution role
output "execution_role_name" {
  description = "ECS Execution Role name"
  value       = local.execution_role_name
}

# Fornece informações sobre estratégia de uso de recursos
# Função: Documentar se cada recurso foi criado novo ou reutilizado existente
# Usa: locals de estratégia (should_use_existing_*)
# Usado por: usuários para entender quais recursos foram criados ou reutilizados
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

# Fornece informações detalhadas de debug sobre descoberta automática
# Função: Facilitar troubleshooting da lógica de descoberta e decisão de recursos
# Usa: local.resource_strategy_debug (inclui descoberta automática e decisões finais)
# Usado por: desenvolvedores para debugar problemas de descoberta de recursos
output "resource_strategy_debug" {
  description = "Debug completo da estratégia de recursos ECS"
  value = local.resource_strategy_debug
}
