# Expõe as URLs dos repositórios ECR (novos e existentes) para outros módulos
# Função: Fornecer URLs completas dos repositórios para push/pull de imagens Docker
# Usa: data.aws_ecr_repository.existing e aws_ecr_repository.services
# Usado por: Módulo ECS para definir image_uri nas task definitions
output "repository_urls" {
  description = "ECR repository URLs"
  value = merge(
    {
      for service, exists in var.existing_resources.ecr_repositories :
      service => exists ? data.aws_ecr_repository.existing[service].repository_url : aws_ecr_repository.services[service].repository_url
      if exists || !exists
    }
  )
}

# Expõe os ARNs dos repositórios ECR para políticas IAM e referências de recursos
# Função: Fornecer identificadores únicos dos repositórios para permissões e políticas
# Usa: data.aws_ecr_repository.existing e aws_ecr_repository.services
# Usado por: Políticas IAM para conceder permissões de push/pull aos serviços ECS
output "repository_arns" {
  description = "ECR repository ARNs"
  value = merge(
    {
      for service, exists in var.existing_resources.ecr_repositories :
      service => exists ? data.aws_ecr_repository.existing[service].arn : aws_ecr_repository.services[service].arn
      if exists || !exists
    }
  )
}

# Expõe os nomes dos repositórios ECR para referência em scripts e automações
# Função: Fornecer nomes simples dos repositórios para uso em CI/CD e deployment scripts
# Usa: data.aws_ecr_repository.existing e aws_ecr_repository.services
# Usado por: Scripts de deployment no GitHub Actions para fazer build e push das imagens
output "repository_names" {
  description = "ECR repository names"
  value = merge(
    {
      for service, exists in var.existing_resources.ecr_repositories :
      service => exists ? data.aws_ecr_repository.existing[service].name : aws_ecr_repository.services[service].name
      if exists || !exists
    }
  )
}