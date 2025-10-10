data "aws_caller_identity" "current" {}

locals {
  cluster_name = "${var.project_name}-cluster"
  role_name    = "${var.project_name}-ecs-execution-role"
}

# Data sources condicionais baseados apenas nos external data providers

# Auto-discovery segura para todos os recursos
# Primeiro, tentamos descobrir quais recursos realmente existem

# Scripts otimizados para descoberta segura e rápida
data "external" "cluster_discovery" {
  program = [
    "bash", "-c",
    "aws --region ${var.aws_region} ecs describe-clusters --clusters '${local.cluster_name}' --query 'length(clusters[?status==`ACTIVE`])' --output text 2>/dev/null | grep -q '^[1-9]' && echo '{\"exists\":\"true\"}' || echo '{\"exists\":\"false\"}'"
  ]
}

data "external" "execution_role_discovery" {
  program = [
    "bash", "-c",
    "aws --region ${var.aws_region} iam get-role --role-name '${local.role_name}' --query 'Role.RoleName' --output text >/dev/null 2>&1 && echo '{\"exists\":\"true\"}' || echo '{\"exists\":\"false\"}'"
  ]
}

# Discovery real para serviços, task definitions e log groups
data "external" "services_discovery" {
  for_each = var.services
  program = [
    "bash", "-c",
    "aws --region ${var.aws_region} ecs describe-services --cluster '${local.cluster_name}' --services '${var.project_name}-${each.key}' --query 'length(services[?status==`ACTIVE`])' --output text 2>/dev/null | grep -q '^[1-9]' && echo '{\"exists\":\"true\"}' || echo '{\"exists\":\"false\"}'"
  ]
}

data "external" "task_definitions_discovery" {
  for_each = var.services
  program = [
    "bash", "-c",
    "aws --region ${var.aws_region} ecs describe-task-definition --task-definition '${var.project_name}-${each.key}' --query 'taskDefinition.taskDefinitionArn' --output text >/dev/null 2>&1 && echo '{\"exists\":\"true\"}' || echo '{\"exists\":\"false\"}'"
  ]
}

data "external" "log_groups_discovery" {
  for_each = var.services
  program = [
    "bash", "-c",
    "aws --region ${var.aws_region} logs describe-log-groups --log-group-name-prefix '/ecs/${var.project_name}/${each.key}' --query 'length(logGroups[?logGroupName==`/ecs/${var.project_name}/${each.key}`])' --output text 2>/dev/null | grep -q '^[1-9]' && echo '{\"exists\":\"true\"}' || echo '{\"exists\":\"false\"}'"
  ]
}

# Removendo data sources que causam dependências circulares
# Toda a lógica de descoberta será feita através dos external data providers

# Locals com lógica simplificada de uso de recursos existentes vs criação de novos
locals {
  # Auto-discovery baseado em external data providers (mais confiável)
  cluster_discovered        = data.external.cluster_discovery.result["exists"] == "true"
  execution_role_discovered = data.external.execution_role_discovery.result["exists"] == "true"

  log_groups_discovered = {
    for k, v in var.services : k => data.external.log_groups_discovery[k].result["exists"] == "true"
  }
  services_discovered = {
    for k, v in var.services : k => data.external.services_discovery[k].result["exists"] == "true"
  }
  task_definitions_discovered = {
    for k, v in var.services : k => data.external.task_definitions_discovery[k].result["exists"] == "true"
  }

  # Lógica final: prioridade para configuração explícita, depois auto-discovery
  should_use_existing_cluster        = var.use_existing_cluster != null ? var.use_existing_cluster : local.cluster_discovered
  should_use_existing_execution_role = var.use_existing_execution_role != null ? var.use_existing_execution_role : local.execution_role_discovered

  should_use_existing_log_groups = {
    for k, v in var.services : k => lookup(var.use_existing_log_groups, k, local.log_groups_discovered[k])
  }
  should_use_existing_services = {
    for k, v in var.services : k => lookup(var.use_existing_services, k, local.services_discovered[k])
  }
  should_use_existing_task_definitions = {
    for k, v in var.services : k => lookup(var.use_existing_task_definitions, k, local.task_definitions_discovered[k])
  }

  # Debug info para transparência
  resource_strategy_debug = {
    cluster        = local.should_use_existing_cluster ? "using-existing" : "creating-new"
    execution_role = local.should_use_existing_execution_role ? "using-existing" : "creating-new"

    auto_discovery_results = {
      cluster_discovered          = local.cluster_discovered
      execution_role_discovered   = local.execution_role_discovered
      log_groups_discovered       = local.log_groups_discovered
      services_discovered         = local.services_discovered
      task_definitions_discovered = local.task_definitions_discovered
    }

    final_decisions = {
      cluster          = local.should_use_existing_cluster
      execution_role   = local.should_use_existing_execution_role
      log_groups       = local.should_use_existing_log_groups
      services         = local.should_use_existing_services
      task_definitions = local.should_use_existing_task_definitions
    }
  }
}

resource "aws_ecs_cluster" "main" {
  count = local.should_use_existing_cluster ? 0 : 1
  name  = local.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "${var.project_name}-cluster"
    Environment = var.environment
    Project     = var.project_name
  }
}
resource "aws_iam_role" "ecs_execution_role" {
  count = local.should_use_existing_execution_role ? 0 : 1
  name  = local.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-ecs-execution-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

# ARNs construídos dinamicamente baseado apenas na external discovery
locals {
  cluster_arn = local.should_use_existing_cluster ? "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${local.cluster_name}" : (length(aws_ecs_cluster.main) > 0 ? aws_ecs_cluster.main[0].arn : "")

  execution_role_arn = local.should_use_existing_execution_role ? "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.role_name}" : (length(aws_iam_role.ecs_execution_role) > 0 ? aws_iam_role.ecs_execution_role[0].arn : "")

  execution_role_name = local.should_use_existing_execution_role ? local.role_name : (length(aws_iam_role.ecs_execution_role) > 0 ? aws_iam_role.ecs_execution_role[0].name : local.role_name)
}

# Policy attachment sempre aplicado (usa role existente ou novo)
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = local.execution_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Policy de secrets sempre aplicada (usa role existente ou novo)
# Implementa lógica "se existir usar, senão criar" para policies também
# CORREÇÃO: Usa apenas wildcard para evitar conflitos com sufixos de ARN dos secrets
# Problema resolvido: ARNs específicos sem sufixo (ex: kavoo-admins-api-db-credentials) 
# não funcionavam com ARNs reais que têm sufixo (ex: kavoo-admins-api-db-credentials-6Fmspt)
resource "aws_iam_role_policy" "secrets_policy" {
  name = "${var.project_name}-ecs-secrets-policy"
  role = local.execution_role_name

  # Lifecycle para seguir filosofia "se existir usar, senão criar"
  # - Novos roles: Criados automaticamente com estrutura correta
  # - Existentes: Mantidos como estão (política só atualiza se conteúdo mudar)
  # - Próximas atualizações: Quando houver necessidade legítima, seguirão novo formato
  lifecycle {
    create_before_destroy = true
  }

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.project_name}-*"
      }
    ]
  })
}

# Policy ECR sempre aplicada (usa role existente ou novo) - CORREÇÃO PARA CannotPullContainerError
resource "aws_iam_role_policy" "ecr_access" {
  name = "${var.project_name}-ecs-ecr-policy"
  role = local.execution_role_name
  
  # Lifecycle para seguir filosofia "se existir usar, senão criar"
  lifecycle {
    create_before_destroy = true
  }
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer", 
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "services" {
  for_each = {
    for k, v in var.services : k => v if !local.should_use_existing_log_groups[k]
  }

  name              = "/ecs/${var.project_name}/${each.key}"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-${each.key}-logs"
    Environment = var.environment
    Project     = var.project_name
    Service     = each.key
  }
}

resource "aws_ecs_task_definition" "services" {
  for_each = {
    for k, v in var.services : k => v if !local.should_use_existing_task_definitions[k]
  }

  family                   = "${var.project_name}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = local.execution_role_arn

  container_definitions = jsonencode([
    {
      name      = each.key
      image     = each.key == "front" ? var.frontend_image_uri : lookup(var.api_image_uris, each.key, "nginx:${lookup(var.service_image_tags, each.key, var.image_tag)}")
      essential = true

      portMappings = [
        {
          containerPort = each.value.port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "NODE_ENV"
          value = var.environment
        },
        {
          name  = "LOG_LEVEL"
          value = var.log_level
        }
      ]

      secrets = each.key == "front" ? [
        {
          name      = "REDIS_URL"
          valueFrom = "${var.secrets_arns.redis_credentials}:redis_url::"
        }
        ] : [
        {
          name      = "DATABASE_URL"
          valueFrom = "${lookup(var.secrets_arns.db_credentials, each.key, "")}:database_url::"
        },
        {
          name      = "REDIS_URL"
          valueFrom = "${var.secrets_arns.redis_credentials}:redis_url::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = local.should_use_existing_log_groups[each.key] ? "/ecs/${var.project_name}/${each.key}" : aws_cloudwatch_log_group.services[each.key].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Name        = "${var.project_name}-${each.key}-task"
    Environment = var.environment
    Project     = var.project_name
    Service     = each.key
  }
}

resource "aws_ecs_service" "services" {
  for_each = {
    for k, v in var.services : k => v if !local.should_use_existing_services[k]
  }

  name            = "${var.project_name}-${each.key}"
  cluster         = local.cluster_arn
  task_definition = local.should_use_existing_task_definitions[each.key] ? "${var.project_name}-${each.key}" : aws_ecs_task_definition.services[each.key].arn
  desired_count   = each.key == "front" ? var.frontend_desired_count : var.api_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    # CORREÇÃO: Sempre usar subnets públicas com IP público para evitar problemas de conectividade
    # com Secrets Manager, ECR e outros serviços AWS quando não há NAT Gateway
    subnets = var.force_network_fix || var.use_public_subnets_for_ecs ? var.public_subnet_ids : (
      var.existing_resources.vpc_exists ? var.public_subnet_ids : var.private_subnet_ids
    )
    security_groups = [var.ecs_security_group_id]
    # CORREÇÃO: Sempre habilitar IP público para garantir conectividade com serviços AWS
    assign_public_ip = var.force_network_fix || var.ecs_assign_public_ip || var.existing_resources.vpc_exists
  }

  dynamic "load_balancer" {
    for_each = each.key == "front" ? [1] : (contains(var.api_services, each.key) ? [1] : [])
    content {
      target_group_arn = each.key == "front" ? var.frontend_target_group_arn : var.api_target_group_arns[each.key]
      container_name   = each.key
      container_port   = each.value.port
    }
  }

  force_new_deployment = true

  tags = {
    Name        = "${var.project_name}-${each.key}"
    Environment = var.environment
    Project     = var.project_name
    Service     = each.key
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_execution_role_policy,
    aws_iam_role_policy.secrets_policy,
    aws_iam_role_policy.ecr_access,
    aws_cloudwatch_log_group.services,
    aws_ecs_task_definition.services
  ]
}
