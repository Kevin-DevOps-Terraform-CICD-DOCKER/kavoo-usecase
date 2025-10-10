# Nome do projeto para padronização de recursos
# Função: Fornecer prefixo único para todos os recursos criados
# Usado por: locals, resources e outputs para nomenclatura consistente
variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}

# Configurações de todos os serviços a serem deployados
# Função: Definir recursos e configurações específicas para cada serviço/container
# Usado por: aws_ecs_task_definition, aws_ecs_service, aws_cloudwatch_log_group para criar recursos por serviço
variable "services" {
  description = "Map of service configurations"
  type = map(object({
    cpu          = number
    memory       = number
    port         = number
    health_path  = string
    min_capacity = number
    max_capacity = number
    priority     = number
  }))
}

variable "api_services" {
  description = "List of API service names"
  type        = list(string)
  default     = [
    "admins-api",
    "checkout-api", 
    "members-api",
    "users-api",
    "webhooks-api"
  ]
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "ECS security group ID"
  type        = string
}

variable "database_endpoints" {
  description = "Map of database endpoints for each API"
  type        = map(string)
}

variable "redis_endpoint" {
  description = "Redis endpoint"
  type        = string
}

# ARNs dos secrets AWS Secrets Manager para injeção nos containers
# Função: Fornecer credenciais seguras (DB, Redis) para os containers via environment secrets
# Usado por: aws_ecs_task_definition para configurar secrets nos container definitions
variable "secrets_arns" {
  description = "Map of secret ARNs"
  type = object({
    app_secrets       = string
    db_credentials    = map(string)
    redis_credentials = string
  })
}

variable "frontend_target_group_arn" {
  description = "Frontend target group ARN"
  type        = string
}

variable "api_target_group_arns" {
  description = "Map of API target group ARNs"
  type        = map(string)
}

variable "alb_listener" {
  description = "ALB listener reference for dependency"
  type        = any
}

# URI da imagem Docker do frontend no ECR
# Função: Especificar qual imagem Docker usar para o container do frontend
# Usado por: aws_ecs_task_definition para definir a imagem do container "front"
variable "frontend_image_uri" {
  description = "Frontend container image URI"
  type        = string
}

# Map de URIs das imagens Docker das APIs no ECR
# Função: Especificar qual imagem Docker usar para cada container de API
# Usado por: aws_ecs_task_definition para definir imagens dos containers de API
variable "api_image_uris" {
  description = "Map of API container image URIs"
  type        = map(string)
}

variable "service_images" {
  description = "Map of service names to their Docker image URLs"
  type        = map(string)
  default     = {}
}

variable "front_image_url" {
  description = "Docker image URL for the frontend service"
  type        = string
  default     = ""
}

variable "frontend_cpu" {
  description = "Frontend task CPU"
  type        = number
  default     = 512
}

variable "frontend_memory" {
  description = "Frontend task memory"
  type        = number
  default     = 1024
}

variable "api_cpu" {
  description = "API task CPU"
  type        = number
  default     = 256
}

variable "api_memory" {
  description = "API task memory"
  type        = number
  default     = 512
}

variable "frontend_desired_count" {
  description = "Desired number of frontend tasks"
  type        = number
  default     = 2
}

variable "api_desired_count" {
  description = "Desired number of API tasks"
  type        = number
  default     = 1
}

variable "log_level" {
  description = "Log level for applications"
  type        = string
  default     = "info"
  validation {
    condition     = contains(["debug", "info", "warning", "error", "critical"], var.log_level)
    error_message = "Log level must be one of: debug, info, warning, error, critical."
  }
}

# Controle manual para usar cluster ECS existente
# Função: Permitir override da descoberta automática de cluster existente
# Usado por: locals.should_use_existing_cluster para decisão final sobre criação/reutilização
variable "use_existing_cluster" {
  description = "Use existing ECS cluster instead of creating a new one (null = auto-discover)"
  type        = bool
  default     = null
}

variable "use_existing_execution_role" {
  description = "Use existing ECS execution role instead of creating a new one (null = auto-discover)"
  type        = bool
  default     = null
}

variable "use_existing_log_groups" {
  description = "Map of services to use existing log groups for (true = use existing, false = create new)"
  type        = map(bool)
  default     = {}
}

variable "use_existing_task_definitions" {
  description = "Map of services to use existing task definitions for (true = use existing, false = create new)"
  type        = map(bool)
  default     = {}
}

variable "use_existing_services" {
  description = "Map of services to use existing ECS services for (true = use existing, false = create new)"
  type        = map(bool)
  default     = {}
}

variable "existing_resources" {
  description = "Configuration for existing AWS resources"
  type = object({
    vpc_exists      = bool
    existing_vpc_id = string
  })
  default = {
    vpc_exists      = false
    existing_vpc_id = null
  }
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

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

# Forçar uso de subnets públicas com IP público para todos os serviços
# Função: Contornar problemas de conectividade evitando NAT Gateway e garantindo acesso a serviços AWS
# Usado por: aws_ecs_service network_configuration para definir subnets e assign_public_ip
variable "force_network_fix" {
  description = "Force network configuration to use public subnets with public IP for all services"
  type        = bool
  default     = true
}

variable "image_tag" {
  description = "Tag da imagem Docker (permite controlar versões específicas ao invés de :latest)"
  type        = string
  default     = "latest"
}

variable "service_image_tags" {
  description = "Map de tags específicas para cada serviço (sobrescreve image_tag global)"
  type        = map(string)
  default     = {}
}


