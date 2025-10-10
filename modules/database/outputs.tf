locals {
  # Mapas condicionais usando lógica "se existir usar, senão criar"
  rds_endpoints_map = merge(
    # Endpoints das databases criadas pelo Terraform (sem porta, apenas hostname)
    {
      for api in keys(local.databases_to_create) : api => split(":", aws_db_instance.main[api].endpoint)[0]
    },
    # Para databases existentes, usar endpoints explícitos definidos (sem porta)
    {
      for api in var.api_services : api => var.existing_db_endpoints[api]
      if !contains(keys(local.databases_to_create), api) && contains(keys(var.existing_db_endpoints), api)
    }
  )
  
  rds_ports_map = {
    for api in var.api_services : api => contains(keys(local.databases_to_create), api) ? aws_db_instance.main[api].port : 5432
  }
}

output "redis_primary_endpoint" {
  description = "Redis primary endpoint"
  value       = length(aws_elasticache_replication_group.main) > 0 ? aws_elasticache_replication_group.main[0].primary_endpoint_address : "redis-not-available"
}

output "redis_reader_endpoint" {
  description = "Redis reader endpoint"  
  value       = length(aws_elasticache_replication_group.main) > 0 ? aws_elasticache_replication_group.main[0].reader_endpoint_address : "redis-not-available"
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = length(aws_elasticache_replication_group.main) > 0 ? aws_elasticache_replication_group.main[0].primary_endpoint_address : "redis-not-available"
}

output "redis_port" {
  description = "Redis port"
  value       = length(aws_elasticache_replication_group.main) > 0 ? aws_elasticache_replication_group.main[0].port : 6379
}

output "redis_cluster_id" {
  description = "Redis cluster ID"
  value       = length(aws_elasticache_replication_group.main) > 0 ? aws_elasticache_replication_group.main[0].id : "redis-not-available"
}

output "rds_instance_ids" {
  description = "Map of RDS instance IDs for each API"
  value = merge(
    # IDs das databases criadas pelo Terraform
    {
      for api in keys(local.databases_to_create) : api => aws_db_instance.main[api].id
    },
    # Para databases existentes, usar convenção de nomes padrão
    {
      for api in var.api_services : api => "${var.project_name}-${var.environment}-${api}-db"
      if !contains(keys(local.databases_to_create), api)
    }
  )
}

output "rds_endpoints" {
  description = "Map of RDS instance endpoints for each API"
  value = local.rds_endpoints_map
}

output "rds_ports" {
  description = "Map of RDS instance ports for each API"  
  value = local.rds_ports_map
}

# Mantém outputs individuais para compatibilidade (pega o primeiro disponível)
output "rds_endpoint" {
  description = "RDS instance endpoint (first available for backward compatibility)"
  value = length(values(local.rds_endpoints_map)) > 0 ? values(local.rds_endpoints_map)[0] : "rds-not-available"
}

output "rds_port" {
  description = "RDS instance port (first available for backward compatibility)" 
  value = length(values(local.rds_ports_map)) > 0 ? values(local.rds_ports_map)[0] : 5432
}

output "db_subnet_group_name" {
  description = "DB subnet group name"
  value       = var.create_subnet_group ? aws_db_subnet_group.main[0].name : data.aws_db_subnet_group.existing[0].name
}

output "cache_subnet_group_name" {
  description = "Cache subnet group name"
  value       = length(aws_elasticache_subnet_group.main) > 0 ? aws_elasticache_subnet_group.main[0].name : "cache-subnet-group-not-created"
}

output "resource_discovery_info" {
  description = "Information about resource usage strategy"
  value = {
    using_existing_rds = {
      for api in var.api_services : api => !contains(keys(local.databases_to_create), api)
    }
    using_existing_redis = !local.should_create_redis
    databases_created = keys(local.databases_to_create)
    databases_existing = [for api in var.api_services : api if !contains(keys(local.databases_to_create), api)]
    redis_action = local.should_create_redis ? "created" : "existing"
  }
}