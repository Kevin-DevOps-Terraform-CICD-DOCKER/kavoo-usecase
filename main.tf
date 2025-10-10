terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge({
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }, var.additional_tags)
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  api_services = ["admins-api", "checkout-api", "members-api", "users-api", "webhooks-api"]

  service_image_urls = {
    for service in local.api_services :
    service => try(
      "${module.ecr.repository_urls[service]}:${lookup(var.service_image_tags, service, var.default_image_tag)}",
      "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/kavoo/${service}:${lookup(var.service_image_tags, service, var.default_image_tag)}"
    )
  }

  front_image_url = try(
    "${module.ecr.repository_urls["front"]}:${lookup(var.service_image_tags, "front", var.default_image_tag)}",
    "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/kavoo/front:${lookup(var.service_image_tags, "front", var.default_image_tag)}"
  )

  all_services = keys(var.services)

  effective_config = {
    db_instance_class          = var.db_instance_class
    redis_node_type            = var.redis_node_type
    enable_multi_az            = var.enable_multi_az
    enable_deletion_protection = var.enable_deletion_protection
    backup_retention_period    = var.backup_retention_period
    monitoring_interval        = var.monitoring_interval
  }
}

module "networking" {
  source = "./modules/networking"

  existing_resources     = var.existing_resources
  project_name           = var.project_name
  environment            = var.environment
  aws_region             = var.aws_region
  vpc_cidr               = var.vpc_cidr
  availability_zones     = var.availability_zones
  public_subnet_cidrs    = var.public_subnet_cidrs
  private_subnet_cidrs   = var.private_subnet_cidrs
  enable_nat_gateway     = var.enable_nat_gateway
  create_security_groups = var.create_security_groups
}

locals {
  debug_networking = {
    vpc_id             = module.networking.vpc_id
    public_subnet_ids  = module.networking.public_subnet_ids
    private_subnet_ids = module.networking.private_subnet_ids
    vpc_exists         = var.existing_resources.vpc_exists
    existing_vpc_id    = var.existing_resources.existing_vpc_id
    subnet_counts = {
      public  = length(module.networking.public_subnet_ids)
      private = length(module.networking.private_subnet_ids)
    }
  }
}

output "debug_networking" {
  description = "Debug information for networking"
  value       = local.debug_networking
}

locals {
  raw_private_subnets = module.networking.private_subnet_ids
  raw_public_subnets  = module.networking.public_subnet_ids

  validated_private_subnets = length(local.raw_private_subnets) >= 2 ? local.raw_private_subnets : (
    length(local.raw_public_subnets) >= 2 ? local.raw_public_subnets :
    concat(local.raw_private_subnets, local.raw_public_subnets)
  )
}

resource "null_resource" "subnet_count_validation" {
  count = length(local.validated_private_subnets) < 2 ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'ERROR: Insufficient subnets for database deployment. Need at least 2, have ${length(local.validated_private_subnets)}' && exit 1"
  }
}

output "debug_subnets" {
  description = "Subnet validation debug"
  value = {
    vpc_exists          = var.existing_resources.vpc_exists
    existing_vpc_id     = var.existing_resources.existing_vpc_id
    raw_private_subnets = local.raw_private_subnets
    raw_public_subnets  = local.raw_public_subnets
    validated_subnets   = local.validated_private_subnets
    subnet_count        = length(local.validated_private_subnets)
    will_work           = length(local.validated_private_subnets) >= 1 ? "MAYBE" : "ERROR"
    error_if_empty      = length(local.validated_private_subnets) == 0 ? "NO SUBNETS FOUND - CHECK VPC CONFIGURATION" : "OK"
  }
}

output "debug_ecs_auto_discovery" {
  description = "ECS auto-discovery debug information"
  value       = module.ecs.resource_strategy_debug
}

module "secrets" {
  source = "./modules/secrets"

  existing_resources = var.existing_resources
  project_name       = var.project_name
  environment        = var.environment
  api_services       = local.api_services
  db_names = {
    "admins-api"   = "kavoo_admins"
    "checkout-api" = "kavoo_checkout"
    "members-api"  = "kavoo_members"
    "users-api"    = "kavoo_users"
    "webhooks-api" = "kavoo_webhooks"
  }
  db_endpoints = module.database.rds_endpoints
  db_passwords = {} # Will use auto-generated passwords
  db_username  = var.db_username
  
  # Configurações para filosofia "se existir usar, senão criar"
  force_recreate_secrets      = {}  # Nenhum forçado por padrão
  force_recreate_redis_secret = false
  force_recreate_app_secret   = false
  aws_region                 = var.aws_region
  redis_host   = module.database.redis_primary_endpoint
  stripe_secret_key = var.stripe_secret_key

  force_update_secrets = var.force_update_secrets

  database_resources_created = {
    for api, using_existing in module.database.resource_discovery_info.using_existing_rds : api => !using_existing
  }

  associated_resources_created = {
    database_created = length([for api, using_existing in module.database.resource_discovery_info.using_existing_rds : api if !using_existing]) > 0
    redis_created    = !module.database.resource_discovery_info.using_existing_redis
  }
}

module "database" {
  source = "./modules/database"

  project_name               = var.project_name
  environment                = var.environment
  private_subnet_ids         = local.validated_private_subnets
  database_security_group_id = module.networking.database_security_group_id
  redis_security_group_id    = module.networking.redis_security_group_id

  api_services = local.api_services
  db_names = {
    "admins-api"   = "kavoo_admins"
    "checkout-api" = "kavoo_checkout"
    "members-api"  = "kavoo_members"
    "users-api"    = "kavoo_users"
    "webhooks-api" = "kavoo_webhooks"
  }
  db_username = var.db_username
  db_passwords = module.secrets.db_passwords
  db_instance_class = local.effective_config.db_instance_class
  postgres_version = var.postgres_version
  
  # Configurações para filosofia "se existir usar, senão criar"
  force_recreate_databases = {}  # Nenhum forçado por padrão
  force_recreate_redis     = false
  aws_region              = var.aws_region

  redis_password  = module.secrets.redis_password
  redis_node_type = local.effective_config.redis_node_type
  redis_num_nodes = var.redis_num_nodes

  enable_multi_az            = local.effective_config.enable_multi_az
  enable_deletion_protection = local.effective_config.enable_deletion_protection
  monitoring_interval        = local.effective_config.monitoring_interval
  enable_rds_monitoring_role = var.enable_rds_monitoring_role
  preferred_az               = length(var.availability_zones) > 0 ? var.availability_zones[0] : null

  create_subnet_group       = var.create_subnet_group
  create_cache_subnet_group = var.create_cache_subnet_group

  # Auto-discovery habilitada (mapas vazios = descobrir automaticamente se recursos existem)
  # Se quiser controle explícito por API, defina no mapa: {"admins-api" = true, "checkout-api" = false}
  use_existing_db    = {}  # Auto-discovery para todas as APIs (padrão)
  use_existing_redis = null  # Auto-discovery (padrão)

  depends_on = [
    module.networking,
    null_resource.subnet_count_validation
  ]
}

module "ecr" {
  source = "./modules/ecr"

  existing_resources = var.existing_resources
  project_name       = var.project_name
  environment        = var.environment
  services           = local.all_services
}

module "load_balancer" {
  source = "./modules/load-balancer"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.networking.vpc_id
  public_subnet_ids     = module.networking.public_subnet_ids
  alb_security_group_id = module.networking.alb_security_group_id

  services     = var.services
  api_services = local.api_services

  certificate_arn            = var.certificate_arn
  domain_name                = var.domain_name
  hosted_zone_id             = var.hosted_zone_id
  enable_deletion_protection = local.effective_config.enable_deletion_protection

  create_load_balancer  = var.create_load_balancer
  create_target_groups  = var.create_target_groups
  create_listener_rules = var.create_listener_rules
  create_listeners      = var.create_listeners
}

module "ecs" {
  source = "./modules/ecs"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  domain_name  = var.domain_name

  services     = var.services
  api_services = local.api_services

  private_subnet_ids    = local.validated_private_subnets
  ecs_security_group_id = module.networking.ecs_security_group_id

  database_endpoints = module.database.rds_endpoints
  redis_endpoint     = module.database.redis_primary_endpoint

  secrets_arns = module.secrets.secrets_arns

  frontend_target_group_arn = module.load_balancer.frontend_target_group_arn
  api_target_group_arns = {
    for k in local.api_services : k => module.load_balancer.target_group_arns[k]
  }

  api_image_uris     = local.service_image_urls
  frontend_image_uri = local.front_image_url

  frontend_cpu           = var.services.front.cpu
  frontend_memory        = var.services.front.memory
  api_cpu                = 256
  api_memory             = 512
  frontend_desired_count = var.services.front.min_capacity
  api_desired_count      = 2
  log_level              = "info"


  # Como os recursos existem, vamos configurar explicitamente para usar existentes
  use_existing_cluster        = true # Cluster kavoo-cluster existe
  use_existing_execution_role = true # Role kavoo-ecs-execution-role existe

  # Todos os serviços existem, então usar os existentes
  use_existing_log_groups = {
    "front"        = true
    "admins-api"   = true
    "checkout-api" = true
    "members-api"  = true
    "users-api"    = true
    "webhooks-api" = true
  }
  use_existing_task_definitions = {
    "front"        = true
    "admins-api"   = true
    "checkout-api" = true
    "members-api"  = true
    "users-api"    = true
    "webhooks-api" = true
  }
  use_existing_services = {
    "front"        = true
    "admins-api"   = true
    "checkout-api" = true
    "members-api"  = true
    "users-api"    = true
    "webhooks-api" = true
  }

  # Adicionar variáveis necessárias para correção de conectividade
  existing_resources         = var.existing_resources
  public_subnet_ids          = module.networking.public_subnet_ids
  use_public_subnets_for_ecs = var.use_public_subnets_for_ecs
  ecs_assign_public_ip       = var.ecs_assign_public_ip
  force_network_fix          = var.force_network_fix

  # Controle de versões das imagens Docker
  image_tag           = var.default_image_tag
  service_image_tags  = var.service_image_tags

  alb_listener = module.load_balancer.primary_listener

  depends_on = [
    module.database,
    module.load_balancer,
    module.secrets,
    module.ecr
  ]
}

module "monitoring" {
  source = "./modules/monitoring"

  existing_resources = {
    budget_exists    = var.existing_resources.budget_exists
    dashboard_exists = var.use_existing_monitoring.dashboard_exists
    alarm_exists     = var.use_existing_monitoring.alarm_exists
  }
  project_name             = var.project_name
  environment              = var.environment
  monthly_budget_limit     = "750"
  budget_alert_threshold_1 = 88
  budget_alert_threshold_2 = 94
  alert_email_addresses    = ["administrativo@kavoo.com"]
}

# Os secrets de database e Redis agora são criados completamente no módulo secrets
# com dados específicos de cada API e lógica condicional "se existir usar, senão criar"

module "smart_deploy" {
  source = "./modules/smart-deploy"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  services = var.services

  frontend_image_uri = local.front_image_url
  api_image_uris     = local.service_image_urls

  enable_health_check     = var.enable_smart_deploy_health_check
  force_health_check      = var.force_smart_deploy_health_check
  always_run_health_check = var.always_run_health_check

  enable_smart_deploy = var.enable_smart_deploy
  force_deploy        = var.force_smart_deploy

  enable_deploy_logging     = var.enable_deploy_logging
  deploy_log_retention_days = var.deploy_log_retention_days

  enable_scheduled_health_check = var.enable_scheduled_health_check
  health_check_schedule         = var.health_check_schedule

  enable_notifications       = var.enable_deploy_notifications
  notification_sns_topic_arn = var.notification_sns_topic_arn
  notification_email         = var.notification_email

  deploy_timeout        = var.deploy_timeout
  max_parallel_builds   = var.max_parallel_builds
  health_check_retries  = var.health_check_retries
  health_check_interval = var.health_check_interval

  additional_tags = var.additional_tags

  depends_on = [
    module.ecs,
    module.ecr,
    module.database,
    module.secrets
  ]
}