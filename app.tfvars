project_name = "kavoo"
environment  = "production"
aws_region   = "us-east-1"

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
enable_nat_gateway   = true

db_name           = "kavoo"
db_username       = "kavoo_user"
db_instance_class = "db.t3.micro"
postgres_version  = "14.15"

redis_node_type = "cache.t3.micro"
redis_num_nodes = 2

domain_name     = "kavoo.com.br"
certificate_arn = ""

enable_multi_az            = false
enable_deletion_protection = false

services = {
  front = {
    cpu          = 512
    memory       = 1024
    port         = 3000
    health_path  = "/health"
    min_capacity = 2
    max_capacity = 6
    priority     = 100
  }
  admins-api = {
    cpu          = 256
    memory       = 512
    port         = 8080
    health_path  = "/health"
    min_capacity = 2
    max_capacity = 4
    priority     = 101
  }
  checkout-api = {
    cpu          = 512
    memory       = 1024
    port         = 8081
    health_path  = "/health"
    min_capacity = 2
    max_capacity = 6
    priority     = 102
  }
  members-api = {
    cpu          = 256
    memory       = 512
    port         = 8082
    health_path  = "/health"
    min_capacity = 2
    max_capacity = 4
    priority     = 103
  }
  users-api = {
    cpu          = 256
    memory       = 512
    port         = 8083
    health_path  = "/health"
    min_capacity = 2
    max_capacity = 4
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

stripe_secret_key = "sk_test_example_stripe_key_for_development_only"

monthly_budget_limit     = "750"
budget_alert_threshold_1 = 88
budget_alert_threshold_2 = 94
alert_email_addresses    = ["administrativo@kavoo.com", "devops@kavoo.com"]

enable_rds_monitoring_role = false
monitoring_interval        = 0

existing_resources = {
  ecr_repositories = {
    "front"        = true
    "admins-api"   = true
    "checkout-api" = true
    "members-api"  = true
    "users-api"    = true
    "webhooks-api" = true
  }
  vpc_exists      = true
  existing_vpc_id = null
  secrets = {
    "kavoo-admins-api-db-credentials"   = true
    "kavoo-checkout-api-db-credentials" = true
    "kavoo-members-api-db-credentials"  = true
    "kavoo-users-api-db-credentials"    = true
    "kavoo-webhooks-api-db-credentials" = true
    "kavoo-redis-credentials"           = true
    "kavoo-app-secrets"                 = true
  }
  budget_exists = true
}

availability_zones = ["us-east-1b", "us-east-1a"]

create_load_balancer      = false
create_target_groups      = false
create_listeners          = false
create_listener_rules     = false
create_subnet_group       = true
create_cache_subnet_group = true

create_security_groups = {
  alb      = false
  ecs      = false
  database = false
  redis    = false
}
use_existing_monitoring = {
  dashboard_exists = false
  alarm_exists     = false
}
force_update_secrets = {
  db_credentials_when_db_created       = true
  redis_credentials_when_redis_created = true
}

enable_smart_deploy_health_check = true
force_smart_deploy_health_check  = false
always_run_health_check          = false

enable_smart_deploy = true
force_smart_deploy  = false

enable_deploy_logging     = true
deploy_log_retention_days = 7

enable_scheduled_health_check = false
health_check_schedule         = "rate(30 minutes)"

enable_deploy_notifications = false
notification_sns_topic_arn  = ""
notification_email          = ""

deploy_timeout        = 1800
max_parallel_builds   = 3
health_check_retries  = 3
health_check_interval = 30

# Configurações de rede para evitar erros de conectividade com Secrets Manager
use_public_subnets_for_ecs = true
ecs_assign_public_ip       = true
force_network_fix          = true