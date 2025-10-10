# Variáveis principais do projeto
variable "project_name" {
  description = "Nome do projeto"
  type        = string
  default     = "kavoo"
}

variable "environment" {
  description = "Ambiente (production, staging, development)"
  type        = string
  default     = "production"
}

variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "services" {
  description = "Mapa de serviços com suas configurações"
  type = map(object({
    cpu    = number
    memory = number
    port   = number
  }))
  default = {
    front = {
      cpu    = 256
      memory = 512
      port   = 3000
    }
    admins-api = {
      cpu    = 256
      memory = 512
      port   = 8080
    }
    checkout-api = {
      cpu    = 256
      memory = 512
      port   = 8081
    }
    members-api = {
      cpu    = 256
      memory = 512
      port   = 8082
    }
    users-api = {
      cpu    = 256
      memory = 512
      port   = 8083
    }
    webhooks-api = {
      cpu    = 256
      memory = 512
      port   = 8084
    }
  }
}

variable "frontend_image_uri" {
  description = "URI da imagem do frontend"
  type        = string
  default     = ""
}

variable "api_image_uris" {
  description = "Mapa com URIs das imagens das APIs"
  type        = map(string)
  default     = {}
}

variable "enable_health_check" {
  description = "Habilita verificação de saúde antes do deploy"
  type        = bool
  default     = true
}

variable "force_health_check" {
  description = "Força execução da verificação de saúde"
  type        = bool
  default     = false
}

variable "always_run_health_check" {
  description = "Sempre executa health check independente de mudanças"
  type        = bool
  default     = false
}

variable "enable_smart_deploy" {
  description = "Habilita análise inteligente de serviços (integrada com GitHub Actions)"
  type        = bool
  default     = true
}

variable "force_deploy" {
  description = "Força análise de todos os serviços (marca todos como precisando deploy)"
  type        = bool
  default     = false
}

variable "enable_deploy_logging" {
  description = "Habilita logs do processo de deploy"
  type        = bool
  default     = true
}

variable "deploy_log_retention_days" {
  description = "Dias de retenção dos logs de deploy"
  type        = number
  default     = 7
}

variable "enable_scheduled_health_check" {
  description = "Habilita verificação de saúde programada via Lambda"
  type        = bool
  default     = false
}

variable "health_check_schedule" {
  description = "Expressão cron para verificação programada (EventBridge format)"
  type        = string
  default     = "rate(30 minutes)"
}

variable "enable_notifications" {
  description = "Habilita notificações sobre status do deploy"
  type        = bool
  default     = false
}

variable "notification_sns_topic_arn" {
  description = "ARN do tópico SNS para notificações"
  type        = string
  default     = ""
}

variable "notification_email" {
  description = "Email para receber notificações"
  type        = string
  default     = ""
}

variable "deploy_timeout" {
  description = "Timeout para operações de deploy (segundos)"
  type        = number
  default     = 1800
}

variable "max_parallel_builds" {
  description = "Número máximo de builds paralelos"
  type        = number
  default     = 3
}

variable "health_check_retries" {
  description = "Número de tentativas para health check"
  type        = number
  default     = 3
}

variable "health_check_interval" {
  description = "Intervalo entre tentativas de health check (segundos)"
  type        = number
  default     = 30
}

variable "additional_tags" {
  description = "Tags adicionais para recursos"
  type        = map(string)
  default     = {}
}