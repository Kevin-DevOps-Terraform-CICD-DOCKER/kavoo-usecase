# Outputs do módulo smart-deploy

output "deployment_info" {
  description = "Informações sobre o status da análise inteligente"
  value = {
    total_services           = length(keys(var.services))
    all_services            = keys(var.services)
    smart_analysis_enabled   = var.enable_smart_deploy
    health_check_enabled     = var.enable_health_check
    last_analysis_timestamp  = timestamp()
    deploy_logging_enabled   = var.enable_deploy_logging
    scheduled_check_enabled  = var.enable_scheduled_health_check
    analysis_mode           = "enabled"
    deployment_mode         = "github_actions"
  }
}

output "useful_commands" {
  description = "Comandos úteis para análise e deploy"
  value = {
    analyze_all_services    = "cd ${path.root} && ./scripts/smart-deploy.sh --analyze-only"
    analyze_to_file        = "cd ${path.root} && ./scripts/smart-deploy.sh --analyze-only --output-file custom.json"
    generate_matrix        = "cd ${path.root} && ./scripts/generate-deploy-matrix.sh"
    check_specific_service = "cd ${path.root} && ./scripts/check-image-health.sh [SERVICE_NAME]"
    manual_deploy_all      = "cd ${path.root} && ./scripts/smart-deploy.sh --build-only"
    manual_deploy_service  = "cd ${path.root} && ./scripts/smart-deploy.sh [SERVICE_NAME] --build-only"
    force_analyze_all      = "cd ${path.root} && ./scripts/smart-deploy.sh --force --analyze-only"
    view_analysis_results  = "cd ${path.root} && cat deploy-matrix.json | jq '.summary'"
  }
}

output "service_status" {
  description = "Status individual de cada serviço"
  value = {
    for service_name, config in var.services : service_name => {
      service_name      = service_name
      cpu_allocation    = config.cpu
      memory_allocation = config.memory
      port             = config.port
      image_uri        = service_name == "front" ? var.frontend_image_uri : lookup(var.api_image_uris, service_name, "")
    }
  }
}

output "health_check_info" {
  description = "Informações sobre verificações de saúde"
  value = {
    enabled                = var.enable_health_check
    scheduled_enabled      = var.enable_scheduled_health_check
    schedule_expression    = var.health_check_schedule
    retries               = var.health_check_retries
    interval_seconds      = var.health_check_interval
    lambda_function_name  = var.enable_scheduled_health_check ? aws_lambda_function.health_checker[0].function_name : null
    cloudwatch_log_group  = var.enable_deploy_logging ? local.log_group_name : null
  }
}

output "deploy_config" {
  description = "Configurações de análise e deploy"
  value = {
    smart_analysis_enabled = var.enable_smart_deploy
    analysis_mode         = "terraform_github_integration"
    force_analysis        = var.force_deploy
    timeout_seconds       = var.deploy_timeout
    max_parallel_builds   = var.max_parallel_builds
    logging_enabled       = var.enable_deploy_logging
    log_retention_days    = var.deploy_log_retention_days
    github_actions_integration = true
    matrix_file_location  = "deploy-matrix.json"
  }
}

output "aws_resources" {
  description = "Recursos AWS criados pelo módulo"
  value = {
    lambda_function_arn    = var.enable_scheduled_health_check ? aws_lambda_function.health_checker[0].arn : null
    iam_role_arn          = var.enable_scheduled_health_check ? aws_iam_role.health_checker_role[0].arn : null
    eventbridge_rule_arn  = var.enable_scheduled_health_check ? aws_cloudwatch_event_rule.health_check_schedule[0].arn : null
    log_group_name        = var.enable_deploy_logging ? local.log_group_name : null
  }
}

output "github_integration_info" {
  description = "Informações sobre integração com GitHub Actions"
  value = {
    workflow_file_path     = ".github/workflows/deploy.yml"
    analysis_step_enabled  = true
    dynamic_matrix_enabled = true
    smart_deploy_mode     = "analysis_only"
    terraform_role        = "analysis_and_infrastructure"
    github_actions_role   = "build_and_deploy"
    matrix_output_file    = "deploy-matrix.json"
    integration_benefits  = [
      "Only necessary services are built and deployed",
      "Reduced CI/CD time and costs",
      "Automatic health checking before deployment",
      "Dynamic service matrix generation",
      "Intelligent resource utilization"
    ]
  }
}

output "notification_config" {
  description = "Configurações de notificação"
  value = {
    enabled           = var.enable_notifications
    sns_topic_arn     = var.notification_sns_topic_arn
    notification_email = var.notification_email
  }
  sensitive = true
}