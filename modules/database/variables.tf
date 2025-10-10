variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "api_services" {
  description = "List of API services that need databases"
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

variable "db_username" {
  description = "Database username (same for all databases)"
  type        = string
  default     = "kavoo_user"
}

variable "db_passwords" {
  description = "Map of database passwords for each API"
  type        = map(string)
  sensitive   = true
}

variable "redis_password" {
  description = "Redis password"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_num_nodes" {
  description = "Number of Redis nodes"
  type        = number
  default     = 2
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "database_security_group_id" { 
  description = "Security group ID for database"
  type        = string
}

variable "redis_security_group_id" { 
  description = "Security group ID for Redis"
  type        = string
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

variable "redis_auth_token" {
  description = "Redis authentication token"
  type        = string
  default     = ""
  sensitive   = true
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

variable "monitoring_interval" {
  description = "Enhanced monitoring interval for RDS"
  type        = number
  default     = 0
}

variable "enable_rds_monitoring_role" {
  description = "Enable creation of RDS monitoring IAM role (requires IAM permissions)"
  type        = bool
  default     = false
}

variable "preferred_az" {
  description = "Preferred availability zone to place the single-AZ RDS instance (optional)."
  type        = string
  default     = ""
}

variable "use_existing_db" {
  description = "Use existing RDS instances instead of creating new ones. If null, will auto-discover per API."
  type        = map(bool)
  default     = {}  # empty = auto-discovery for all, map per API to override
}

variable "use_existing_redis" {
  description = "Use existing Redis cluster instead of creating a new one. If null, will auto-discover."
  type        = bool
  default     = null  # null = auto-discovery, true = force use existing, false = force create new
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "14.15"
}

variable "force_recreate_databases" {
  description = "Force recreation of specific databases even if they exist"
  type        = map(bool)
  default     = {}
}

variable "force_recreate_redis" {
  description = "Force recreation of Redis even if it exists"
  type        = bool
  default     = false
}

variable "aws_region" {
  description = "AWS region for resource discovery"
  type        = string
  default     = "us-east-1"
}

variable "existing_db_endpoints" {
  description = "Map of existing database endpoints (without port) for APIs that should use existing databases"
  type        = map(string)
  default = {
    "admins-api"   = "kavoo-production-admins-api-db.ci9eo4aqg1sj.us-east-1.rds.amazonaws.com"
    "checkout-api" = "kavoo-production-checkout-api-db.ci9eo4aqg1sj.us-east-1.rds.amazonaws.com"
    "members-api"  = "kavoo-production-members-api-db.ci9eo4aqg1sj.us-east-1.rds.amazonaws.com"
    "users-api"    = "kavoo-production-users-api-db.ci9eo4aqg1sj.us-east-1.rds.amazonaws.com"
    "webhooks-api" = "kavoo-production-webhooks-api-db.ci9eo4aqg1sj.us-east-1.rds.amazonaws.com"
  }
}