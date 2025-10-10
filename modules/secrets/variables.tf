variable "project_name" {
  description = "Project name"
  type        = string

  validation {
    condition     = length(var.project_name) > 0 && length(var.project_name) <= 50
    error_message = "Project name must be between 1 and 50 characters."
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be one of: production, staging, development."
  }
}

variable "api_services" {
  description = "List of API services that need database secrets"
  type        = list(string)
  default     = ["admins-api", "checkout-api", "members-api", "users-api", "webhooks-api"]
}

variable "db_names" {
  description = "Map of database names for each API"
  type        = map(string)
  default = {
    "admins-api"   = "kavoo_admins"
    "checkout-api" = "kavoo_checkout"
    "members-api"  = "kavoo_members"
    "users-api"    = "kavoo_users"
    "webhooks-api" = "kavoo_webhooks"
  }
}

variable "db_endpoints" {
  description = "Map of database endpoints for each API"
  type        = map(string)
  default     = {}
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "kavoo_admin"

  validation {
    condition     = length(var.db_username) >= 3 && length(var.db_username) <= 63
    error_message = "Database username must be between 3 and 63 characters."
  }
}

variable "db_passwords" {
  description = "Map of database passwords for each API"
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "redis_host" {
  description = "Redis host endpoint" 
  type        = string
  default     = "localhost"

  validation {
    condition     = var.redis_host != ""
    error_message = "Redis host cannot be empty."
  }
}

variable "stripe_secret_key" {
  description = "Stripe secret key for payments"
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.stripe_secret_key == "" || can(regex("^sk_(test_|live_).+", var.stripe_secret_key))
    error_message = "Stripe secret key must be empty or start with 'sk_test_' or 'sk_live_'."
  }
}

variable "enable_secret_rotation" {
  description = "Enable automatic secret rotation"
  type        = bool
  default     = false
}

variable "secret_recovery_window_days" {
  description = "Number of days to retain deleted secrets for recovery"
  type        = number
  default     = 7

  validation {
    condition     = var.secret_recovery_window_days >= 7 && var.secret_recovery_window_days <= 30
    error_message = "Secret recovery window must be between 7 and 30 days."
  }
}

variable "existing_resources" {
  description = "Configuration for existing AWS resources"
  type = object({
    secrets = map(bool)
  })
  default = {
    secrets = {}
  }
}

variable "redis_auth_token" {
  description = "Redis authentication token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "force_update_secrets" {
  description = "Configuration to force update secrets when associated resources are created"
  type = object({
    db_credentials_when_db_created      = bool
    redis_credentials_when_redis_created = bool
  })
  default = {
    db_credentials_when_db_created      = false
    redis_credentials_when_redis_created = false
  }
}

variable "database_resources_created" {
  description = "Map indicating which database resources were created in this run (per API)"
  type        = map(bool)
  default     = {}
}

variable "associated_resources_created" {
  description = "Information about whether associated resources were created in this run"
  type = object({
    database_created = bool
    redis_created    = bool
  })
  default = {
    database_created = false
    redis_created    = false
  }
}

variable "recovery_window_in_days" {
  description = "Number of days that AWS Secrets Manager waits before it can delete the secret"
  type        = number
  default     = 0
}

variable "force_recreate_secrets" {
  description = "Force recreation of specific secrets even if they exist"
  type        = map(bool)
  default     = {}
}

variable "force_recreate_redis_secret" {
  description = "Force recreation of Redis secret even if it exists"
  type        = bool
  default     = false
}

variable "force_recreate_app_secret" {
  description = "Force recreation of app secret even if it exists"
  type        = bool
  default     = false
}

variable "aws_region" {
  description = "AWS region for resource discovery"
  type        = string
  default     = "us-east-1"
}