# Local values
locals {
  log_group_name = "/aws/deploy/${var.project_name}"
}

resource "null_resource" "health_check" {
  for_each = var.services

  triggers = {
    service_name = each.key
    image_uri    = each.key == "front" ? var.frontend_image_uri : lookup(var.api_image_uris, each.key, "")
    force_check  = var.force_health_check ? timestamp() : ""
    always_run   = var.always_run_health_check
  }

  provisioner "local-exec" {
    command = "${path.module}/../../scripts/check-image-health.sh ${each.key}"
    
    environment = {
      PROJECT_NAME   = var.project_name
      ENVIRONMENT    = var.environment
      AWS_REGION     = var.aws_region
      AWS_ACCOUNT_ID = data.aws_caller_identity.current.account_id
    }
    
    on_failure = continue
  }

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_caller_identity" "current" {}

# Abordagem simplificada - o smart deploy verifica internamente quais serviços precisam
# de deploy, eliminando a necessidade de data sources externos complexos

# Recurso para executar análise inteligente (não faz deploy, apenas análise)
resource "null_resource" "smart_deploy_analysis" {
  count = var.enable_smart_deploy ? 1 : 0

  triggers = {
    services_hash = md5(join(",", keys(var.services)))
    force_analysis = var.force_deploy ? timestamp() : ""
    analysis_mode = "true"  # Sempre modo análise
  }

  # Executa apenas análise, não deploy
  provisioner "local-exec" {
    command = <<-EOT
      cd "${path.module}/../.."
      
      # Verifica se os scripts existem
      if [ ! -f "./scripts/check-image-health.sh" ] || [ ! -f "./scripts/smart-deploy.sh" ]; then
        echo "[WARNING] Scripts de análise não encontrados. Criando placeholder..."
        echo '{"services":[],"summary":{"timestamp":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'","total_services":0,"needs_deploy":0,"already_healthy":0}}' > deploy-matrix.json
        exit 0
      fi
      
      # Torna os scripts executáveis se necessário
      chmod +x ./scripts/check-image-health.sh 2>/dev/null || true
      chmod +x ./scripts/smart-deploy.sh 2>/dev/null || true
      chmod +x ./scripts/generate-deploy-matrix.sh 2>/dev/null || true
      
      # Executa apenas análise (não deploy)
      echo "[INFO] Executando análise inteligente de serviços..."
      if ./scripts/smart-deploy.sh --analyze-only --output-file deploy-matrix.json; then
        echo "[SUCCESS] Análise inteligente concluída com sucesso"
        
        # Mostra resumo da análise
        if [ -f "deploy-matrix.json" ]; then
          echo "[INFO] Resumo da análise:"
          cat deploy-matrix.json | jq -r '
            "Total de serviços: " + (.summary.total_services | tostring) + "\n" +
            "Precisam de deploy: " + (.summary.needs_deploy | tostring) + "\n" +
            "Já saudáveis: " + (.summary.already_healthy | tostring)
          ' 2>/dev/null || echo "Arquivo de análise criado"
        fi
      else
        echo "[WARNING] Análise falhou, criando análise padrão"
        echo '{"services":[],"summary":{"timestamp":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'","total_services":0,"needs_deploy":0,"already_healthy":0,"error":"analysis_failed"}}' > deploy-matrix.json
      fi
    EOT
    
    environment = {
      PROJECT_NAME   = var.project_name
      ENVIRONMENT    = var.environment
      AWS_REGION     = var.aws_region
      AWS_ACCOUNT_ID = data.aws_caller_identity.current.account_id
    }
  }

  depends_on = [
    null_resource.health_check
  ]
}

# Null resource para criar log group apenas se não existir
resource "null_resource" "create_log_group_if_not_exists" {
  count = var.enable_deploy_logging ? 1 : 0
  
  triggers = {
    log_group_name = local.log_group_name
    retention_days = var.deploy_log_retention_days
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      # Verifica se o log group já existe
      if ! aws logs describe-log-groups \
        --log-group-name-prefix "${local.log_group_name}" \
        --region "${var.aws_region}" \
        --query 'logGroups[?logGroupName==`${local.log_group_name}`]' \
        --output text | grep -q "${local.log_group_name}"; then
        
        echo "Criando log group: ${local.log_group_name}"
        aws logs create-log-group \
          --log-group-name "${local.log_group_name}" \
          --region "${var.aws_region}"
        
        # Define retenção
        aws logs put-retention-policy \
          --log-group-name "${local.log_group_name}" \
          --retention-in-days ${var.deploy_log_retention_days} \
          --region "${var.aws_region}"
          
        # Adiciona tags
        aws logs tag-log-group \
          --log-group-name "${local.log_group_name}" \
          --tags "Name=${var.project_name}-deploy-logs,Environment=${var.environment},Project=${var.project_name},Purpose=SmartDeploy" \
          --region "${var.aws_region}"
      else
        echo "Log group ${local.log_group_name} já existe, pulando criação"
      fi
    EOT
  }
}

resource "aws_lambda_function" "health_checker" {
  count = var.enable_scheduled_health_check ? 1 : 0
  
  filename         = data.archive_file.health_checker_zip[0].output_path
  function_name    = "${var.project_name}-health-checker"
  role            = aws_iam_role.health_checker_role[0].arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 300
  
  source_code_hash = data.archive_file.health_checker_zip[0].output_base64sha256
  
  environment {
    variables = {
      PROJECT_NAME = var.project_name
      ENVIRONMENT  = var.environment
      AWS_REGION   = var.aws_region
    }
  }
  
  tags = {
    Name        = "${var.project_name}-health-checker"
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "ScheduledHealthCheck"
  }
}

data "archive_file" "health_checker_zip" {
  count = var.enable_scheduled_health_check ? 1 : 0
  
  type        = "zip"
  output_path = "/tmp/${var.project_name}-health-checker.zip"
  
  source {
    content = templatefile("${path.module}/templates/health_checker.py", {
      project_name = var.project_name
      environment  = var.environment
    })
    filename = "index.py"
  }
}

resource "aws_iam_role" "health_checker_role" {
  count = var.enable_scheduled_health_check ? 1 : 0
  
  name = "${var.project_name}-health-checker-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "health_checker_policy" {
  count = var.enable_scheduled_health_check ? 1 : 0
  
  name = "${var.project_name}-health-checker-policy"
  role = aws_iam_role.health_checker_role[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeClusters",
          "ecs:DescribeTaskDefinition",
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "health_check_schedule" {
  count = var.enable_scheduled_health_check ? 1 : 0
  
  name                = "${var.project_name}-health-check-schedule"
  description         = "Trigger for periodic health checks"
  schedule_expression = var.health_check_schedule
}

resource "aws_cloudwatch_event_target" "health_checker_target" {
  count = var.enable_scheduled_health_check ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.health_check_schedule[0].name
  target_id = "HealthCheckerTarget"
  arn       = aws_lambda_function.health_checker[0].arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  count = var.enable_scheduled_health_check ? 1 : 0
  
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.health_checker[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.health_check_schedule[0].arn
}