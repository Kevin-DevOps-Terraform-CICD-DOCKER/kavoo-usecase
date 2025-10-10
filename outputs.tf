output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.networking.private_subnet_ids
}

output "rds_endpoints" {
  description = "Map of RDS instance endpoints for each API"
  value       = module.database.rds_endpoints
}

output "rds_endpoint" {
  description = "RDS instance endpoint (first available for backward compatibility)"
  value       = module.database.rds_endpoint
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.database.redis_primary_endpoint
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = module.ecs.cluster_arn
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.load_balancer.alb_dns_name
}

output "alb_zone_id" {
  description = "ALB zone ID"
  value       = module.load_balancer.alb_zone_id
}

output "ecr_repositories" {
  description = "ECR repository URLs"
  value       = module.ecr.repository_urls
}

output "secrets_arns" {
  description = "ARNs of all secrets"
  value       = module.secrets.secrets_arns
}

output "application_url" {
  description = "Application URL"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "http://${module.load_balancer.alb_dns_name}"
}

output "database_passwords" {
  description = "Map of database passwords for each API (sensitive)"
  value       = module.secrets.db_passwords
  sensitive   = true
}

output "database_password" {
  description = "Database password (first API for backward compatibility)"
  value       = module.secrets.db_password
  sensitive   = true
}

output "redis_password" {
  description = "Redis password (sensitive)"
  value       = module.secrets.redis_password
  sensitive   = true
}

output "secrets_manager_console_links" {
  description = "Direct links to AWS Secrets Manager console"
  value = {
    database_credentials = {
      admins   = "https://console.aws.amazon.com/secretsmanager/secret?name=kavoo-admins-api-db-credentials&region=${var.aws_region}"
      checkout = "https://console.aws.amazon.com/secretsmanager/secret?name=kavoo-checkout-api-db-credentials&region=${var.aws_region}"
      members  = "https://console.aws.amazon.com/secretsmanager/secret?name=kavoo-members-api-db-credentials&region=${var.aws_region}"
      users    = "https://console.aws.amazon.com/secretsmanager/secret?name=kavoo-users-api-db-credentials&region=${var.aws_region}"
      webhooks = "https://console.aws.amazon.com/secretsmanager/secret?name=kavoo-webhooks-api-db-credentials&region=${var.aws_region}"
    }
    redis_credentials = "https://console.aws.amazon.com/secretsmanager/secret?name=kavoo-redis-credentials&region=${var.aws_region}"
    app_secrets       = "https://console.aws.amazon.com/secretsmanager/secret?name=kavoo-app-secrets&region=${var.aws_region}"
  }
}

output "connection_strings" {
  description = "Database connection information"
  value = {
    postgres_endpoints = module.database.rds_endpoints
    redis_endpoint     = module.database.redis_primary_endpoint
    database_names = {
      "admins-api"   = "kavoo_admins"
      "checkout-api" = "kavoo_checkout"
      "members-api"  = "kavoo_members"
      "users-api"    = "kavoo_users"
      "webhooks-api" = "kavoo_webhooks"
    }
    database_user = var.db_username
  }
  sensitive = true
}

output "smart_deploy_info" {
  description = "Smart deploy configuration and status"
  value       = module.smart_deploy.deployment_info
}

output "smart_deploy_commands" {
  description = "Useful commands for smart deployment"
  value       = module.smart_deploy.useful_commands
}

output "service_status" {
  description = "Status of each service"
  value       = module.smart_deploy.service_status
}

output "health_check_info" {
  description = "Health check configuration and status"
  value       = module.smart_deploy.health_check_info
}

output "deploy_config" {
  description = "Deployment configuration"
  value       = module.smart_deploy.deploy_config
}

output "smart_deploy_aws_resources" {
  description = "AWS resources created by smart deploy module"
  value       = module.smart_deploy.aws_resources
}