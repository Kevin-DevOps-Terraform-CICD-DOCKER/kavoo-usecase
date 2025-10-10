terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_db_subnet_group" "existing" {
  count = var.create_subnet_group ? 0 : 1
  name  = "${var.project_name}-${var.environment}-db-subnet-group"
}

data "aws_elasticache_subnet_group" "existing" {
  count = var.create_cache_subnet_group ? 0 : 1
  name  = "${var.project_name}-${var.environment}-cache-subnet-group"
}

# ================================
# DATABASE MODULE - FILOSOFIA "SE EXISTIR USAR, SENÃO CRIAR"
# Uses static variable-based logic instead of external data sources
# to avoid Terraform "unknown value" errors while maintaining
# "if exists use, else create" philosophy
# ================================

# Lógica de decisão baseada em variáveis estáticas
locals {
  # Decisão final: criar apenas se explicitamente solicitado via variáveis
  databases_to_create = {
    for api in var.api_services : api => api 
    if !lookup(var.use_existing_db, api, true) || lookup(var.force_recreate_databases, api, false)
  }
  
  should_create_redis = local.redis_can_be_created && (var.use_existing_redis == null ? false : !var.use_existing_redis || var.force_recreate_redis)
}



resource "aws_db_subnet_group" "main" {
  count      = var.create_subnet_group ? 1 : 0
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  lifecycle {
    precondition {
      condition     = length(var.private_subnet_ids) >= 2
      error_message = "At least two private subnet IDs are required for DB subnet group. Received ${length(var.private_subnet_ids)} subnets."
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  }
}

locals {
  # Simplified logic - create all databases (Terraform will detect existing ones via state)
  # Subnet validation
  redis_can_be_created = length(var.private_subnet_ids) >= 2
  
  subnet_ids_to_use = var.private_subnet_ids
}

resource "aws_elasticache_subnet_group" "main" {
  count      = var.create_cache_subnet_group ? 1 : 0
  name       = "${var.project_name}-${var.environment}-cache-subnet-group"
  subnet_ids = local.subnet_ids_to_use

  tags = {
    Name = "${var.project_name}-${var.environment}-cache-subnet-group"
  }
}

resource "aws_iam_role" "rds_monitoring_role" {
  count = var.monitoring_interval > 0 && var.enable_rds_monitoring_role ? 1 : 0
  name  = "${var.project_name}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-rds-monitoring-role"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring_role_policy" {
  count      = var.monitoring_interval > 0 && var.enable_rds_monitoring_role ? 1 : 0
  role       = aws_iam_role.rds_monitoring_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "main" {
  for_each = local.databases_to_create
  
  identifier     = "${var.project_name}-${var.environment}-${each.key}-db"
  engine         = "postgres"
  engine_version = var.postgres_version
  instance_class = var.db_instance_class
  
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = false
  
  db_name  = lookup(var.db_names, each.key, "kavoo_${replace(each.key, "-api", "")}")
  username = var.db_username
  password = lookup(var.db_passwords, each.key, "default_password")

  vpc_security_group_ids = [var.database_security_group_id]
  db_subnet_group_name   = var.create_subnet_group ? aws_db_subnet_group.main[0].name : data.aws_db_subnet_group.existing[0].name
  
  multi_az                = false
  backup_retention_period = var.environment == "production" ? 7 : 0
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  skip_final_snapshot = var.environment != "production"
  deletion_protection = var.enable_deletion_protection
  publicly_accessible  = false
  
  monitoring_interval = 0
  monitoring_role_arn = null
  
  enabled_cloudwatch_logs_exports = []
  
  availability_zone = null

  tags = {
    Name = "${var.project_name}-${each.key}-db"
    API  = each.key
  }
}

resource "aws_elasticache_replication_group" "main" {
  count = local.should_create_redis ? 1 : 0
  
  replication_group_id       = "${var.project_name}-${var.environment}-redis"
  description                = "Redis cluster for ${var.project_name}-${var.environment}"
  
  node_type                  = var.redis_node_type
  port                       = 6379
  parameter_group_name       = "default.redis7"
  
  num_cache_clusters         = 1
  multi_az_enabled           = false
  automatic_failover_enabled = false
  
  subnet_group_name          = var.create_cache_subnet_group ? aws_elasticache_subnet_group.main[0].name : data.aws_elasticache_subnet_group.existing[0].name
  security_group_ids         = [var.redis_security_group_id]
  
  auth_token                 = null
  transit_encryption_enabled = false
  at_rest_encryption_enabled = false

  tags = {
    Name = "${var.project_name}-redis"
  }
}