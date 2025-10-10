# ================================
# SECRETS MODULE - FILOSOFIA "SE EXISTIR USAR, SENÃO CRIAR"
# ================================

# Descoberta automática de secrets existentes
data "external" "db_secrets_discovery" {
  for_each = toset(var.api_services)
  program = [
    "bash", "-c",
    "aws secretsmanager describe-secret --secret-id 'kavoo-${each.key}-db-credentials' --region ${var.aws_region} --query 'Name' --output text >/dev/null 2>&1 && echo '{\"exists\":\"true\"}' || echo '{\"exists\":\"false\"}'"
  ]
}

data "external" "redis_secret_discovery" {
  program = [
    "bash", "-c",
    "aws secretsmanager describe-secret --secret-id 'kavoo-redis-credentials' --region ${var.aws_region} --query 'Name' --output text >/dev/null 2>&1 && echo '{\"exists\":\"true\"}' || echo '{\"exists\":\"false\"}'"
  ]
}

data "external" "app_secret_discovery" {
  program = [
    "bash", "-c", 
    "aws secretsmanager describe-secret --secret-id 'kavoo-app-secrets' --region ${var.aws_region} --query 'Name' --output text >/dev/null 2>&1 && echo '{\"exists\":\"true\"}' || echo '{\"exists\":\"false\"}'"
  ]
}

locals {
  # Descoberta automática
  existing_db_secrets = {
    for api in var.api_services : api => data.external.db_secrets_discovery[api].result["exists"] == "true"
  }
  redis_secret_exists = data.external.redis_secret_discovery.result["exists"] == "true"
  app_secret_exists   = data.external.app_secret_discovery.result["exists"] == "true"
  
  # Decisão final: criar apenas se não existir OU se forçado
  db_secrets_to_create = {
    for api in var.api_services : api => api 
    if !local.existing_db_secrets[api] || lookup(var.force_recreate_secrets, api, false)
  }
  
  should_create_redis_secret = !local.redis_secret_exists || var.force_recreate_redis_secret
  should_create_app_secret   = !local.app_secret_exists || var.force_recreate_app_secret
}

# ================================
# RANDOM PASSWORDS
# ================================

resource "random_password" "db_passwords" {
  for_each = local.db_secrets_to_create
  
  length  = 32
  special = true
  override_special = "!#$%&*()_+-=[]{}|;:,.<>?"
  
  keepers = {
    api = each.key
    # Force new password when database is recreated
    version = lookup(var.database_resources_created, each.key, false) && var.force_update_secrets.db_credentials_when_db_created ? timestamp() : "1"
  }
}

resource "random_password" "redis_password" {
  length  = 32
  special = false
  
  keepers = {
    # Force new password when Redis is recreated
    version = var.associated_resources_created.redis_created && var.force_update_secrets.redis_credentials_when_redis_created ? timestamp() : "1"
  }
}

resource "random_password" "redis_auth_token" {
  length  = 32
  special = false
  
  keepers = {
    # Force new token when Redis is recreated
    version = var.associated_resources_created.redis_created && var.force_update_secrets.redis_credentials_when_redis_created ? timestamp() : "1"
  }
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "random_password" "encryption_key" {
  length  = 32
  special = false
}

resource "random_password" "nextauth_secret" {
  length = 64
  special = true
  override_special = "!#$%&*()_+-=[]{}|;:,.<>?"
}

resource "random_password" "webhooks_secret" {
  length = 64
  special = true
  override_special = "!#$%&*()_+-=[]{}|;:,.<>?"
}

# ================================
# SECRETS MANAGER RESOURCES
# ================================

resource "aws_secretsmanager_secret" "db_credentials" {
  for_each = local.db_secrets_to_create
  
  name        = "kavoo-${each.key}-db-credentials"
  description = "Database credentials for kavoo ${each.key}"
  
  recovery_window_in_days = var.recovery_window_in_days
  
  tags = {
    Name        = "kavoo-${each.key}-db-credentials"
    Environment = var.environment
    API         = each.key
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  for_each = local.db_secrets_to_create
  
  secret_id = aws_secretsmanager_secret.db_credentials[each.key].id
    
  secret_string = jsonencode({
    database_url = "postgresql://${var.db_username}:${random_password.db_passwords[each.key].result}@${split(":", lookup(var.db_endpoints, each.key, "localhost"))[0]}:5432/${lookup(var.db_names, each.key, "kavoo_${replace(each.key, "-api", "")}")}"
    dbname       = lookup(var.db_names, each.key, "kavoo_${replace(each.key, "-api", "")}")
    engine       = "postgres"
    host         = split(":", lookup(var.db_endpoints, each.key, "localhost"))[0]
    password     = random_password.db_passwords[each.key].result
    port         = 5432
    username     = var.db_username
  })
}

resource "aws_secretsmanager_secret" "redis_credentials" {
  count = local.should_create_redis_secret ? 1 : 0
  
  name        = "kavoo-redis-credentials"
  description = "Redis credentials for kavoo"
  
  recovery_window_in_days = var.recovery_window_in_days
  
  tags = {
    Name        = "kavoo-redis-credentials"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "redis_credentials" {
  count     = local.should_create_redis_secret ? 1 : 0
  secret_id = aws_secretsmanager_secret.redis_credentials[0].id
  
  secret_string = jsonencode({
    host       = var.redis_host
    port       = 6379
    password   = random_password.redis_password.result
    auth_token = random_password.redis_auth_token.result
    redis_url  = "redis://:${random_password.redis_password.result}@${var.redis_host}:6379"
  })
}

resource "aws_secretsmanager_secret" "app_secrets" {
  count = local.should_create_app_secret ? 1 : 0
  
  name        = "kavoo-app-secrets"
  description = "Application secrets for kavoo"
  
  recovery_window_in_days = var.recovery_window_in_days
  
  tags = {
    Name        = "kavoo-app-secrets"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "app_secrets" {
  count     = local.should_create_app_secret ? 1 : 0
  secret_id = aws_secretsmanager_secret.app_secrets[0].id
  
  secret_string = jsonencode({
    stripe_secret_key = var.stripe_secret_key
    jwt_secret        = random_password.jwt_secret.result
    encryption_key    = random_password.encryption_key.result
    nextauth_secret   = random_password.nextauth_secret.result
    webhooks_secret   = random_password.webhooks_secret.result
  })
}