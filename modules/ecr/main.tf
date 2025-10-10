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

data "aws_ecr_repository" "existing" {
  for_each = {
    for service, exists in var.existing_resources.ecr_repositories :
    service => service if exists
  }
  
  name = "kavoo/${each.key}"
}

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