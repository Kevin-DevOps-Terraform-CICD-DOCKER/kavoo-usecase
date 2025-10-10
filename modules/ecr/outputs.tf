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