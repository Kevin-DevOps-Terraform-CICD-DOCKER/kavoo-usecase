# Cria repositórios ECR (Elastic Container Registry) apenas para serviços que ainda não existem
# Função: Armazenar imagens Docker dos microserviços da aplicação
# Usa: var.existing_resources para verificar quais repositórios já existem
# Usado por: ECS services para fazer pull das imagens Docker
resource "aws_ecr_repository" "services" {
  for_each = {
    for service, exists in var.existing_resources.ecr_repositories :
    service => service if !exists
  }
  
  name                 = "kavoo/${each.key}"
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "kavoo-${each.key}"
  }
}

# Busca informações de repositórios ECR que já existem na AWS
# Função: Obter dados de repositórios ECR pré-existentes para reutilizar
# Usa: var.existing_resources para identificar quais repositórios já existem
# Usado por: outputs para fornecer URLs e ARNs dos repositórios existentes
data "aws_ecr_repository" "existing" {
  for_each = {
    for service, exists in var.existing_resources.ecr_repositories :
    service => service if exists
  }
  
  name = "kavoo/${each.key}"
}

# Define políticas de ciclo de vida para gerenciar automaticamente as imagens nos repositórios ECR
# Função: Controlar retenção de imagens para economizar espaço de armazenamento e custos
# Usa: aws_ecr_repository.services (apenas para repositórios criados por este módulo)
# Ação: Remove automaticamente imagens antigas (mantém últimas 10 com tag "v" e remove sem tag após 1 dia)
resource "aws_ecr_lifecycle_policy" "services" {
  for_each = aws_ecr_repository.services

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}