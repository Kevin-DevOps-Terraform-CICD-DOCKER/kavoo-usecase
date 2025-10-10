# Obtém informações da conta AWS atual (Account ID)
# Função: Fornecer dados da conta AWS para construir ARNs de recursos
# Usa: Nenhuma variável específica
# Usado por: locals para construir ARNs de cluster e execution role
data "aws_caller_identity" "current" {}

# Define nomes padronizados para recursos ECS
# Função: Padronizar nomenclatura de recursos baseada no nome do projeto
# Usa: var.project_name para criar nomes únicos
# Usado por: todos os recursos ECS e IAM do módulo
locals {
  cluster_name = "${var.project_name}-cluster"
  role_name    = "${var.project_name}-ecs-execution-role"
}
# Verifica se cluster ECS já existe na AWS
# Função: Auto-descobrir cluster existente para evitar duplicação de recursos
# Usa: var.aws_region, local.cluster_name
# Usado por: locals para decidir se deve criar ou usar cluster existente
data "external" "cluster_discovery" {
  program = [
    "bash", "-c",
    "aws --region ${var.aws_region} ecs describe-clusters --clusters '${local.cluster_name}' --query 'length(clusters[?status==`ACTIVE`])' --output text 2>/dev/null | grep -q '^[1-9]' && echo '{\"exists\":\"true\"}' || echo '{\"exists\":\"false\"}'"
  ]
}

# Verifica se role de execução ECS já existe no IAM
# Função: Auto-descobrir execution role existente para evitar duplicação de recursos
# Usa: var.aws_region, local.role_name
# Usado por: locals para decidir se deve criar ou usar execution role existente
data "external" "execution_role_discovery" {
  program = [
    "bash", "-c",
    "aws --region ${var.aws_region} iam get-role --role-name '${local.role_name}' --query 'Role.RoleName' --output text >/dev/null 2>&1 && echo '{\"exists\":\"true\"}' || echo '{\"exists\":\"false\"}'"
  ]
}
# Verifica se serviços ECS já existem no cluster
# Função: Auto-descobrir serviços ECS existentes para cada service configurado
# Usa: var.services, var.aws_region, var.project_name, local.cluster_name
# Usado por: locals para decidir se deve criar ou usar serviços existentes
data "external" "services_discovery" {
  for_each = var.services
  program = [
    "bash", "-c",
    "aws --region ${var.aws_region} ecs describe-services --cluster '${local.cluster_name}' --services '${var.project_name}-${each.key}' --query 'length(services[?status==`ACTIVE`])' --output text 2>/dev/null | grep -q '^[1-9]' && echo '{\"exists\":\"true\"}' || echo '{\"exists\":\"false\"}'"
  ]
}

# Verifica se task definitions ECS já existem
# Função: Auto-descobrir task definitions existentes para cada serviço
# Usa: var.services, var.aws_region, var.project_name
# Usado por: locals para decidir se deve criar ou usar task definitions existentes
data "external" "task_definitions_discovery" {
  for_each = var.services
  program = [
    "bash", "-c",
    "aws --region ${var.aws_region} ecs describe-task-definition --task-definition '${var.project_name}-${each.key}' --query 'taskDefinition.taskDefinitionArn' --output text >/dev/null 2>&1 && echo '{\"exists\":\"true\"}' || echo '{\"exists\":\"false\"}'"
  ]
}

# Verifica se log groups CloudWatch já existem
# Função: Auto-descobrir log groups existentes para cada serviço
# Usa: var.services, var.aws_region, var.project_name
# Usado por: locals para decidir se deve criar ou usar log groups existentes
data "external" "log_groups_discovery" {
  for_each = var.services
  program = [
    "bash", "-c",
    "aws --region ${var.aws_region} logs describe-log-groups --log-group-name-prefix '/ecs/${var.project_name}/${each.key}' --query 'length(logGroups[?logGroupName==`/ecs/${var.project_name}/${each.key}`])' --output text 2>/dev/null | grep -q '^[1-9]' && echo '{\"exists\":\"true\"}' || echo '{\"exists\":\"false\"}'"
  ]
}
# Processa resultados de descoberta automática e define estratégia de recursos
# Função: Decidir se usar recursos existentes ou criar novos baseado em descoberta automática e configurações manuais
# Usa: data.external discovery results, var.use_existing_*, var.services
# Usado por: recursos ECS para determinar count e referências
locals {
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

# Cria cluster ECS se não existir
# Função: Provisionar cluster ECS com Container Insights habilitado para monitoramento
# Usa: local.should_use_existing_cluster, local.cluster_name, var.project_name, var.environment
# Usado por: locals.cluster_arn e aws_ecs_service para referenciar o cluster
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
# Cria role IAM para execução de tarefas ECS se não existir
# Função: Provisionar role IAM que permite ao ECS assumir e executar tarefas
# Usa: local.should_use_existing_execution_role, local.role_name, var.project_name, var.environment
# Usado por: aws_ecs_task_definition para execution_role_arn e aws_iam_role_policy para anexar políticas
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

# Define ARNs e nomes de recursos baseado na estratégia de uso (existente ou novo)
# Função: Fornecer ARNs consistentes independente se recurso é existente ou novo
# Usa: local.should_use_existing_*, data.aws_caller_identity, var.aws_region, aws_ecs_cluster, aws_iam_role
# Usado por: aws_ecs_service, aws_ecs_task_definition, outputs
locals {
  cluster_arn = local.should_use_existing_cluster ? "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${local.cluster_name}" : (length(aws_ecs_cluster.main) > 0 ? aws_ecs_cluster.main[0].arn : "")

  execution_role_arn = local.should_use_existing_execution_role ? "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.role_name}" : (length(aws_iam_role.ecs_execution_role) > 0 ? aws_iam_role.ecs_execution_role[0].arn : "")

  execution_role_name = local.should_use_existing_execution_role ? local.role_name : (length(aws_iam_role.ecs_execution_role) > 0 ? aws_iam_role.ecs_execution_role[0].name : local.role_name)
}

# Anexa política AWS gerenciada para execução de tarefas ECS
# Função: Fornecer permissões básicas para ECS (ECR, CloudWatch Logs)
# Usa: local.execution_role_name
# Usado por: aws_ecs_service como dependência para garantir permissões antes da criação
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = local.execution_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Cria política IAM para acesso ao AWS Secrets Manager
# Função: Permitir que tarefas ECS acessem secrets específicos do projeto
# Usa: var.project_name, local.execution_role_name, var.aws_region
# Usado por: aws_ecs_service como dependência para garantir acesso aos secrets
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

# Cria política IAM para acesso ao ECR e CloudWatch Logs
# Função: Permitir que tarefas ECS baixem imagens Docker do ECR e enviem logs
# Usa: var.project_name, local.execution_role_name
# Usado por: aws_ecs_service como dependência para garantir acesso ao ECR e logs
resource "aws_iam_role_policy" "ecr_access" {
  name = "${var.project_name}-ecs-ecr-policy"
  role = local.execution_role_name
  
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

# Cria log groups CloudWatch para serviços ECS se não existirem
# Função: Fornecer destino para logs dos containers com retenção de 7 dias
# Usa: var.services, local.should_use_existing_log_groups, var.project_name, var.environment
# Usado por: aws_ecs_task_definition para configurar log driver dos containers
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

# Cria task definitions ECS para serviços se não existirem
# Função: Definir configuração de containers (CPU, memória, imagem, variáveis, secrets)
# Usa: var.services, local.should_use_existing_task_definitions, var.project_name, var.frontend_image_uri, var.api_image_uris, var.secrets_arns, var.environment, var.log_level, var.aws_region
# Usado por: aws_ecs_service para especificar qual task definition executar
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

# Cria serviços ECS para executar containers se não existirem
# Função: Executar e manter containers rodando com configuração de rede e load balancer
# Usa: var.services, local.should_use_existing_services, var.project_name, local.cluster_arn, var.frontend_desired_count, var.api_desired_count, var.public_subnet_ids, var.private_subnet_ids, var.ecs_security_group_id, var.frontend_target_group_arn, var.api_target_group_arns
# Usado por: Load balancer para direcionar tráfego aos containers em execução
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
    subnets = var.force_network_fix || var.use_public_subnets_for_ecs ? var.public_subnet_ids : (
      var.existing_resources.vpc_exists ? var.public_subnet_ids : var.private_subnet_ids
    )
    security_groups = [var.ecs_security_group_id]
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
