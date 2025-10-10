output "db_passwords" {
  description = "Generated database passwords for each API"
  value = {
    for api in var.api_services : api => contains(keys(local.db_secrets_to_create), api) ? random_password.db_passwords[api].result : "existing"
  }
  sensitive = true
}

# Mantém output individual para compatibilidade (pega o primeiro)
output "db_password" {
  description = "Generated database password (first API for backward compatibility)"
  value = length(var.api_services) > 0 && contains(keys(local.db_secrets_to_create), var.api_services[0]) ? random_password.db_passwords[var.api_services[0]].result : "existing_or_no_apis"
  sensitive = true
}

output "redis_password" {
  description = "Generated Redis password"
  value       = random_password.redis_password.result
  sensitive   = true
}

output "secrets_arns" {
  description = "ARNs of the secrets"
  value = {
    app_secrets = local.should_create_app_secret ? aws_secretsmanager_secret.app_secrets[0].arn : "arn:aws:secretsmanager:${var.aws_region}:*:secret:kavoo-app-secrets"
    db_credentials = {
      for api in var.api_services : api => contains(keys(local.db_secrets_to_create), api) ? aws_secretsmanager_secret.db_credentials[api].arn : "arn:aws:secretsmanager:${var.aws_region}:*:secret:kavoo-${api}-db-credentials"
    }
    redis_credentials = local.should_create_redis_secret ? aws_secretsmanager_secret.redis_credentials[0].arn : "arn:aws:secretsmanager:${var.aws_region}:*:secret:kavoo-redis-credentials"
  }
}

output "secrets_names" {
  description = "Names of the secrets"
  value = {
    app_secrets = local.should_create_app_secret ? aws_secretsmanager_secret.app_secrets[0].name : "kavoo-app-secrets"
    db_credentials = {
      for api in var.api_services : api => contains(keys(local.db_secrets_to_create), api) ? aws_secretsmanager_secret.db_credentials[api].name : "kavoo-${api}-db-credentials"
    }
    redis_credentials = local.should_create_redis_secret ? aws_secretsmanager_secret.redis_credentials[0].name : "kavoo-redis-credentials"
  }
}

output "secrets_discovery_summary" {
  description = "Summary of secrets created for each API"
  value = {
    db_credentials = {
      for api in var.api_services : api => {
        secret_name = contains(keys(local.db_secrets_to_create), api) ? aws_secretsmanager_secret.db_credentials[api].name : "kavoo-${api}-db-credentials"
        secret_arn = contains(keys(local.db_secrets_to_create), api) ? aws_secretsmanager_secret.db_credentials[api].arn : "arn:aws:secretsmanager:${var.aws_region}:*:secret:kavoo-${api}-db-credentials"
        database_recreated = lookup(var.database_resources_created, api, false)
        action = contains(keys(local.db_secrets_to_create), api) ? "created" : "existing"
      }
    }
    redis_credentials = {
      secret_name = local.should_create_redis_secret ? aws_secretsmanager_secret.redis_credentials[0].name : "kavoo-redis-credentials"
      secret_arn = local.should_create_redis_secret ? aws_secretsmanager_secret.redis_credentials[0].arn : "arn:aws:secretsmanager:${var.aws_region}:*:secret:kavoo-redis-credentials"
      action = local.should_create_redis_secret ? "created" : "existing"
    }
    app_secrets = {
      secret_name = local.should_create_app_secret ? aws_secretsmanager_secret.app_secrets[0].name : "kavoo-app-secrets"
      secret_arn = local.should_create_app_secret ? aws_secretsmanager_secret.app_secrets[0].arn : "arn:aws:secretsmanager:${var.aws_region}:*:secret:kavoo-app-secrets"
      action = local.should_create_app_secret ? "created" : "existing"
    }
  }
}