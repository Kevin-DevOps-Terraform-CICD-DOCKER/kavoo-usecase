# Basic Configuration
variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
  validation {
    condition     = contains(["us-east-1", "us-west-2", "eu-west-1"], var.aws_region)
    error_message = "AWS region must be one of: us-east-1, us-west-2, eu-west-1."
  }
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "kavoo"
  validation {
    condition     = length(var.project_name) > 0 && length(var.project_name) <= 20
    error_message = "Project name must be between 1 and 20 characters."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least 2 public subnets are required for high availability."
  }
}

variable "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least 2 private subnets are required for high availability."
  }
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "kavoo"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db_name))
    error_message = "Database name must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "kavoo_user"
  sensitive   = true
  validation {
    condition     = length(var.db_username) >= 3
    error_message = "Database username must be at least 3 characters long."
  }
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
  validation {
    condition     = can(regex("^db\\.(t3|t4g|r5|r6g)\\.(micro|small|medium|large|xlarge)", var.db_instance_class))
    error_message = "Database instance class must be a valid RDS instance type."
  }
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "14.15"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 and 65536 GB."
  }
}

variable "max_allocated_storage" {
  description = "Maximum allocated storage in GB"
  type        = number
  default     = 100
}

variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 0 and 35 days."
  }
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
  validation {
    condition     = can(regex("^cache\\.(t3|t4g|r5|r6g)\\.(micro|small|medium|large|xlarge)", var.redis_node_type))
    error_message = "Redis node type must be a valid ElastiCache instance type."
  }
}

variable "redis_num_nodes" {
  description = "Number of Redis nodes"
  type        = number
  default     = 2
  validation {
    condition     = var.redis_num_nodes >= 1 && var.redis_num_nodes <= 20
    error_message = "Number of Redis nodes must be between 1 and 20."
  }
}

variable "redis_parameter_group_name" {
  description = "Redis parameter group name"
  type        = string
  default     = "default.redis7"
}

variable "enable_multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "auto_minor_version_upgrade" {
  description = "Enable auto minor version upgrade"
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "kavoo.com.br"
  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?)*$", var.domain_name))
    error_message = "Domain name must be a valid domain format."
  }
}

variable "certificate_arn" {
  description = "ARN of the SSL certificate"
  type        = string
}

variable "services" {
  description = "ECS services configuration"
  type = map(object({
    cpu          = number
    memory       = number
    port         = number
    health_path  = string
    min_capacity = number
    max_capacity = number
    priority     = number
  }))

  default = {
    front = {
      cpu          = 512
      memory       = 1024
      port         = 3000
      health_path  = "/health"
      min_capacity = 2
      max_capacity = 8
      priority     = 100
    }
    admins-api = {
      cpu          = 256
      memory       = 512
      port         = 8080
      health_path  = "/health"
      min_capacity = 1
      max_capacity = 3
      priority     = 101
    }
    checkout-api = {
      cpu          = 1024
      memory       = 2048
      port         = 8081
      health_path  = "/health"
      min_capacity = 3
      max_capacity = 8
      priority     = 102
    }
    members-api = {
      cpu          = 512
      memory       = 1024
      port         = 8082
      health_path  = "/health"
      min_capacity = 2
      max_capacity = 4
      priority     = 103
    }
    users-api = {
      cpu          = 512
      memory       = 1024
      port         = 8083
      health_path  = "/health"
      min_capacity = 2
      max_capacity = 6
      priority     = 104
    }
    webhooks-api = {
      cpu          = 256
      memory       = 512
      port         = 8084
      health_path  = "/health"
      min_capacity = 2
      max_capacity = 4
      priority     = 105
    }
  }
}

variable "stripe_secret_key" {
  description = "Stripe secret key"
  type        = string
  sensitive   = true
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval for RDS (0, 1, 5, 10, 15, 30, 60)"
  type        = number
  default     = 60
  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights for RDS"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period (7-731 days)"
  type        = number
  default     = 7
  validation {
    condition     = var.performance_insights_retention_period >= 7 && var.performance_insights_retention_period <= 731
    error_message = "Performance Insights retention period must be between 7 and 731 days."
  }
}

variable "environment_config" {
  description = "Environment-specific configurations"
  type = object({
    db_instance_class          = string
    redis_node_type            = string
    enable_multi_az            = bool
    enable_deletion_protection = bool
    backup_retention_period    = number
    monitoring_interval        = number
  })

  default = {
    db_instance_class          = "db.t3.small"
    redis_node_type            = "cache.t3.small"
    enable_multi_az            = true
    enable_deletion_protection = true
    backup_retention_period    = 7
    monitoring_interval        = 60
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD"
  type        = string
  default     = "600"

  validation {
    condition     = can(tonumber(var.monthly_budget_limit))
    error_message = "Monthly budget limit must be a valid number."
  }
}

variable "budget_alert_threshold_1" {
  description = "First budget alert threshold (percentage)"
  type        = number
  default     = 80

  validation {
    condition     = var.budget_alert_threshold_1 > 0 && var.budget_alert_threshold_1 <= 100
    error_message = "Budget alert threshold must be between 1 and 100."
  }
}

variable "budget_alert_threshold_2" {
  description = "Second budget alert threshold (percentage)"
  type        = number
  default     = 95

  validation {
    condition     = var.budget_alert_threshold_2 > 0 && var.budget_alert_threshold_2 <= 100
    error_message = "Budget alert threshold must be between 1 and 100."
  }
}

variable "alert_email_addresses" {
  description = "List of email addresses for budget alerts"
  type        = list(string)
  default     = ["admin@kavoo.com"]

  validation {
    condition     = length(var.alert_email_addresses) > 0
    error_message = "At least one email address must be provided for alerts."
  }
}

variable "admin_email" {
  description = "Admin email for notifications"
  type        = string
  default     = "admin@kavoo.com"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.admin_email))
    error_message = "Admin email must be a valid email address."
  }
}

variable "redis_auth_token" {
  description = "Authentication token for Redis cluster"
  type        = string
  default     = ""
  sensitive   = true
  validation {
    condition = var.redis_auth_token == "" || (
      length(var.redis_auth_token) >= 16 &&
      length(var.redis_auth_token) <= 128 &&
      can(regex("^[a-zA-Z0-9!@#$%^&*()_+=-]+$", var.redis_auth_token))
    )
    error_message = "Redis auth token must be 16-128 characters with alphanumeric and special characters."
  }
}

variable "existing_resources" {
  description = "Configuration for existing AWS resources"
  type = object({
    ecr_repositories = map(bool)
    vpc_exists       = bool
    existing_vpc_id  = string
    secrets          = map(bool)
    budget_exists    = bool
  })
  default = {
    ecr_repositories = {
      "front"        = false
      "admins-api"   = false
      "checkout-api" = false
      "members-api"  = false
      "users-api"    = false
      "webhooks-api" = false
    }
    vpc_exists      = false
    existing_vpc_id = null
    secrets = {
      "kavoo-admins-api-db-credentials"   = false
      "kavoo-checkout-api-db-credentials" = false
      "kavoo-members-api-db-credentials"  = false
      "kavoo-users-api-db-credentials"    = false
      "kavoo-webhooks-api-db-credentials" = false
      "kavoo-redis-credentials"           = false
      "kavoo-app-secrets"                 = false
    }
    budget_exists = false
  }

  validation {
    condition     = length(var.existing_resources.ecr_repositories) > 0
    error_message = "At least one ECR repository configuration must be provided."
  }
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1b", "us-east-1a"]
}

variable "create_load_balancer" {
  description = "Whether to create the load balancer"
  type        = bool
  default     = true
}

variable "create_target_groups" {
  description = "Whether to create target groups"
  type        = bool
  default     = true
}

variable "create_subnet_group" {
  description = "Whether to create the DB subnet group"
  type        = bool
  default     = true
}

variable "create_cache_subnet_group" {
  description = "Whether to create the ElastiCache subnet group"
  type        = bool
  default     = true
}

variable "enable_rds_monitoring_role" {
  description = "Enable creation of RDS monitoring IAM role (requires IAM permissions)"
  type        = bool
  default     = false
}

variable "create_security_groups" {
  description = "Whether to create new security groups or use existing ones"
  type = object({
    alb      = bool
    ecs      = bool
    database = bool
    redis    = bool
  })
  default = {
    alb      = true
    ecs      = true
    database = true
    redis    = true
  }
}

variable "use_existing_db" {
  description = "Whether to use an existing RDS instance instead of creating a new one"
  type        = bool
  default     = false
}

variable "use_existing_redis" {
  description = "Whether to use an existing Redis cluster instead of creating a new one"
  type        = bool
  default     = false
}

variable "use_existing_log_groups" {
  description = "Whether to use existing CloudWatch Log Groups instead of creating new ones"
  type        = bool
  default     = false
}

variable "use_existing_iam_roles" {
  description = "Whether to use existing IAM roles instead of creating new ones"
  type        = bool
  default     = false
}

variable "create_listener_rules" {
  description = "Whether to create new listener rules or use existing ones"
  type        = bool
  default     = true
}

variable "create_listeners" {
  description = "Whether to create new listeners (HTTP/HTTPS) or use existing ones"
  type        = bool
  default     = true
}

# Novas variáveis para ECS
variable "use_existing_cluster" {
  description = "Whether to use existing ECS cluster instead of creating a new one"
  type        = bool
  default     = false
}

variable "use_existing_task_definitions" {
  description = "Whether to use existing ECS task definitions instead of creating new ones"
  type        = bool
  default     = false
}

variable "use_existing_services" {
  description = "Whether to use existing ECS services instead of creating new ones"
  type        = bool
  default     = false
}

variable "use_existing_monitoring" {
  description = "Configuration for existing monitoring resources"
  type = object({
    dashboard_exists = bool
    alarm_exists     = bool
  })
  default = {
    dashboard_exists = false
    alarm_exists     = false
  }
}

variable "force_update_secrets" {
  description = "Configuration to force update secrets when associated resources are created"
  type = object({
    db_credentials_when_db_created       = bool
    redis_credentials_when_redis_created = bool
  })
  default = {
    db_credentials_when_db_created       = true
    redis_credentials_when_redis_created = true
  }
}
variable "enable_smart_deploy_health_check" {
  description = "Enable health checks before deploying services"
  type        = bool
  default     = true
}

variable "force_smart_deploy_health_check" {
  description = "Force health check execution even when not needed"
  type        = bool
  default     = false
}

variable "always_run_health_check" {
  description = "Always run health check regardless of changes"
  type        = bool
  default     = false
}

variable "enable_smart_deploy" {
  description = "Enable smart deploy (only deploy services that need it)"
  type        = bool
  default     = true
}

variable "force_smart_deploy" {
  description = "Force deploy of all services regardless of health status"
  type        = bool
  default     = false
}

variable "enable_deploy_logging" {
  description = "Enable logging for deployment process"
  type        = bool
  default     = true
}

variable "deploy_log_retention_days" {
  description = "Number of days to retain deployment logs"
  type        = number
  default     = 7
  validation {
    condition     = var.deploy_log_retention_days >= 1 && var.deploy_log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

variable "enable_scheduled_health_check" {
  description = "Enable scheduled health checks via Lambda"
  type        = bool
  default     = false
}

variable "health_check_schedule" {
  description = "Schedule expression for health checks (EventBridge format)"
  type        = string
  default     = "rate(30 minutes)"
  validation {
    condition     = can(regex("^(rate\\(\\d+\\s+(minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.health_check_schedule))
    error_message = "Health check schedule must be a valid EventBridge schedule expression."
  }
}

variable "enable_deploy_notifications" {
  description = "Enable notifications for deployment status"
  type        = bool
  default     = false
}

variable "notification_sns_topic_arn" {
  description = "SNS topic ARN for deployment notifications"
  type        = string
  default     = ""
}

variable "notification_email" {
  description = "Email address for deployment notifications"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

variable "deploy_timeout" {
  description = "Timeout for deployment operations (seconds)"
  type        = number
  default     = 1800
  validation {
    condition     = var.deploy_timeout >= 60 && var.deploy_timeout <= 7200
    error_message = "Deploy timeout must be between 60 and 7200 seconds."
  }
}

variable "max_parallel_builds" {
  description = "Maximum number of parallel builds"
  type        = number
  default     = 3
  validation {
    condition     = var.max_parallel_builds >= 1 && var.max_parallel_builds <= 10
    error_message = "Max parallel builds must be between 1 and 10."
  }
}

variable "health_check_retries" {
  description = "Number of retries for health checks"
  type        = number
  default     = 3
  validation {
    condition     = var.health_check_retries >= 1 && var.health_check_retries <= 10
    error_message = "Health check retries must be between 1 and 10."
  }
}

variable "health_check_interval" {
  description = "Interval between health check attempts (seconds)"
  type        = number
  default     = 30
  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

# Network Configuration Variables for ECS
variable "use_public_subnets_for_ecs" {
  description = "Use public subnets for ECS services to avoid NAT Gateway costs and connectivity issues"
  type        = bool
  default     = true
}

variable "ecs_assign_public_ip" {
  description = "Assign public IP to ECS tasks for AWS services connectivity (Secrets Manager, ECR)"
  type        = bool
  default     = true
}

variable "force_network_fix" {
  description = "Force network configuration to use public subnets with public IP for all services"
  type        = bool
  default     = true
}

# Docker Image Configuration
variable "default_image_tag" {
  description = "Tag padrão para todas as imagens Docker (pode ser sobrescrito por serviço)"
  type        = string
  default     = "latest"
}

variable "service_image_tags" {
  description = "Map de tags específicas por serviço (sobrescreve default_image_tag)"
  type        = map(string)
  default     = {}
  
  # Exemplo de uso:
  # service_image_tags = {
  #   "checkout-api" = "v1.2.3"
  #   "users-api"    = "v1.1.0"
  #   "front"        = "v2.0.1"
  # }
}