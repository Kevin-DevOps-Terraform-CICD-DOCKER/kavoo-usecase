# Nome do projeto usado para identificação e tags dos recursos
# Função: Padronizar nomenclatura e organização dos recursos AWS
# Usado por: Tags e identificação dos recursos ECR
variable "project_name" {
  description = "Project name"
  type        = string
}

# Nome do ambiente (production, staging, development) para separação de recursos
# Função: Diferenciar recursos por ambiente e aplicar configurações específicas
# Usado por: Tags e identificação dos recursos ECR
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

# Lista dos microserviços que precisam de repositórios ECR para armazenar imagens Docker
# Função: Definir quais serviços da aplicação terão repositórios ECR criados
# Usado por: Loop for_each para criar repositórios individuais para cada serviço
variable "services" {
  description = "List of service names for ECR repositories"
  type        = list(string)
  default     = [
    "front",
    "admins-api",
    "checkout-api", 
    "members-api",
    "users-api",
    "webhooks-api"
  ]
}

# Mapeamento de recursos ECR existentes para evitar conflitos e reutilizar recursos
# Função: Controlar quais repositórios já existem (true) vs quais devem ser criados (false)
# Usado por: Lógica condicional em main.tf para decidir entre criar novo ou usar existente
# Recebido de: Módulo raiz que detecta recursos AWS pré-existentes
variable "existing_resources" {
  description = "Configuration for existing AWS resources"
  type = object({
    ecr_repositories = map(bool)
  })
}
