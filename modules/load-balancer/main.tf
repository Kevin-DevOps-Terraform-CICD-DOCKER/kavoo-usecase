data "external" "check_lb_resources_exist" {
  count = 1
  
  program = ["bash", "-c", <<-EOT
    # Verificar se frontend target group existe
    if aws elbv2 describe-target-groups --names "${var.project_name}-frontend-tg" --query 'TargetGroups[0].TargetGroupName' --output text 2>/dev/null | grep -q "${var.project_name}-frontend-tg"; then
      frontend_exists="true"
    else
      frontend_exists="false"
    fi
    
    # Verificar cada API target group
    checkout_exists="false"
    if aws elbv2 describe-target-groups --names "${var.project_name}-checkout-api-tg" --query 'TargetGroups[0].TargetGroupName' --output text 2>/dev/null | grep -q "${var.project_name}-checkout-api-tg"; then
      checkout_exists="true"
    fi
    
    users_exists="false"
    if aws elbv2 describe-target-groups --names "${var.project_name}-users-api-tg" --query 'TargetGroups[0].TargetGroupName' --output text 2>/dev/null | grep -q "${var.project_name}-users-api-tg"; then
      users_exists="true"
    fi
    
    admins_exists="false"
    if aws elbv2 describe-target-groups --names "${var.project_name}-admins-api-tg" --query 'TargetGroups[0].TargetGroupName' --output text 2>/dev/null | grep -q "${var.project_name}-admins-api-tg"; then
      admins_exists="true"
    fi
    
    members_exists="false"
    if aws elbv2 describe-target-groups --names "${var.project_name}-members-api-tg" --query 'TargetGroups[0].TargetGroupName' --output text 2>/dev/null | grep -q "${var.project_name}-members-api-tg"; then
      members_exists="true"
    fi
    
    webhooks_exists="false"
    if aws elbv2 describe-target-groups --names "${var.project_name}-webhooks-api-tg" --query 'TargetGroups[0].TargetGroupName' --output text 2>/dev/null | grep -q "${var.project_name}-webhooks-api-tg"; then
      webhooks_exists="true"
    fi
    
    # Verificar se listener rules existem (se ALB existe)
    # Função para verificar se recurso existe (retorna true/false)
    resource_exists() {
      if eval "$1" &>/dev/null; then echo "true"; else echo "false"; fi
    }
    
    # Verificar se ALB existe
    alb_exists=$(resource_exists "aws elbv2 describe-load-balancers --names 'kavoo-alb' --query 'LoadBalancers[0].LoadBalancerName' --output text")
    
    # Verificar listener rules se ALB existe
    checkout_rule_exists="false"
    users_rule_exists="false" 
    admins_rule_exists="false"
    members_rule_exists="false"
    webhooks_rule_exists="false"
    
    if [ "$alb_exists" = "true" ]; then
      # Buscar ARN do ALB
      alb_arn=$(aws elbv2 describe-load-balancers --names "kavoo-alb" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
      
      if [ "$alb_arn" != "" ] && [ "$alb_arn" != "None" ]; then
        # Buscar listeners do ALB
        listeners=$(aws elbv2 describe-listeners --load-balancer-arn "$alb_arn" --query 'Listeners[*].ListenerArn' --output text 2>/dev/null)
        
        for listener_arn in $listeners; do
          if [ "$listener_arn" != "" ] && [ "$listener_arn" != "None" ]; then
            # Verificar rules deste listener de forma mais robusta
            if aws elbv2 describe-rules --listener-arn "$listener_arn" --query 'Rules[?Conditions[?Field==`path-pattern` && Values[?contains(@, `/api/checkout-api/`)]]]' --output text 2>/dev/null | grep -q .; then
              checkout_rule_exists="true"
            fi
            if aws elbv2 describe-rules --listener-arn "$listener_arn" --query 'Rules[?Conditions[?Field==`path-pattern` && Values[?contains(@, `/api/users-api/`)]]]' --output text 2>/dev/null | grep -q .; then
              users_rule_exists="true"
            fi
            if aws elbv2 describe-rules --listener-arn "$listener_arn" --query 'Rules[?Conditions[?Field==`path-pattern` && Values[?contains(@, `/api/admins-api/`)]]]' --output text 2>/dev/null | grep -q .; then
              admins_rule_exists="true"
            fi
            if aws elbv2 describe-rules --listener-arn "$listener_arn" --query 'Rules[?Conditions[?Field==`path-pattern` && Values[?contains(@, `/api/members-api/`)]]]' --output text 2>/dev/null | grep -q .; then
              members_rule_exists="true"
            fi
            if aws elbv2 describe-rules --listener-arn "$listener_arn" --query 'Rules[?Conditions[?Field==`path-pattern` && Values[?contains(@, `/api/webhooks-api/`)]]]' --output text 2>/dev/null | grep -q .; then
              webhooks_rule_exists="true"
            fi
          fi
        done
      fi
    fi
    
    # Retornar JSON válido usando cat EOF
    cat << EOF
{
  "frontend_exists": "$frontend_exists",
  "checkout_api_exists": "$checkout_exists", 
  "users_api_exists": "$users_exists",
  "admins_api_exists": "$admins_exists",
  "members_api_exists": "$members_exists",
  "webhooks_api_exists": "$webhooks_exists",
  "checkout_rule_exists": "$checkout_rule_exists",
  "users_rule_exists": "$users_rule_exists", 
  "admins_rule_exists": "$admins_rule_exists",
  "members_rule_exists": "$members_rule_exists",
  "webhooks_rule_exists": "$webhooks_rule_exists",
  "alb_exists": "$alb_exists"
}
EOF
  EOT
  ]
}

data "aws_lb" "existing" {
  count = var.create_load_balancer ? 0 : 1
  name  = "kavoo-alb"
}

data "aws_lb_listener" "existing_http" {
  count             = var.create_load_balancer || var.create_listeners ? 0 : 1
  load_balancer_arn = data.aws_lb.existing[0].arn
  port              = 80
}

data "aws_lb_listener" "existing_https" {
  count             = var.create_load_balancer || var.create_listeners || var.certificate_arn == "" ? 0 : 1
  load_balancer_arn = data.aws_lb.existing[0].arn
  port              = 443
}

resource "aws_lb" "main" {
  count              = var.create_load_balancer ? 1 : 0
  name               = "kavoo-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  tags = {
    Name = "${var.project_name}-alb"
  }
}

locals {
  alb_arn      = var.create_load_balancer ? aws_lb.main[0].arn : data.aws_lb.existing[0].arn
  alb_dns_name = var.create_load_balancer ? aws_lb.main[0].dns_name : data.aws_lb.existing[0].dns_name
  alb_zone_id  = var.create_load_balancer ? aws_lb.main[0].zone_id : data.aws_lb.existing[0].zone_id
  
  lb_resources_check_result = try(data.external.check_lb_resources_exist[0].result, {})
  
  frontend_tg_exists = (try(local.lb_resources_check_result.frontend_exists, "false") == "true")
  api_target_groups_exist = {
    "checkout-api" = (try(local.lb_resources_check_result.checkout_api_exists, "false") == "true")
    "users-api"    = (try(local.lb_resources_check_result.users_api_exists, "false") == "true")
    "admins-api"   = (try(local.lb_resources_check_result.admins_api_exists, "false") == "true")
    "members-api"  = (try(local.lb_resources_check_result.members_api_exists, "false") == "true")
    "webhooks-api" = (try(local.lb_resources_check_result.webhooks_api_exists, "false") == "true")
  }
  
  api_listener_rules_exist = {
    "checkout-api" = (try(local.lb_resources_check_result.checkout_rule_exists, "false") == "true")
    "users-api"    = (try(local.lb_resources_check_result.users_rule_exists, "false") == "true")
    "admins-api"   = (try(local.lb_resources_check_result.admins_rule_exists, "false") == "true")
    "members-api"  = (try(local.lb_resources_check_result.members_rule_exists, "false") == "true")
    "webhooks-api" = (try(local.lb_resources_check_result.webhooks_rule_exists, "false") == "true")
  }
  
  api_services_set = toset(var.api_services)
  
  existing_api_tg_set = var.create_target_groups ? toset([]) : toset([
    for service in var.api_services : service
    if local.api_target_groups_exist[service]
  ])
  
  should_create_frontend_tg = var.create_target_groups || !local.frontend_tg_exists
  
  api_tgs_to_create = toset([
    for service in var.api_services : service
    if var.create_target_groups || !local.api_target_groups_exist[service]
  ])
  
  api_rules_to_create = toset([
    for service in var.api_services : service
    if var.create_listener_rules || !local.api_listener_rules_exist[service]
  ])
  
  should_create_listeners = var.create_load_balancer || var.create_listeners
  
  http_listener_arn = local.should_create_listeners ? try(aws_lb_listener.main[0].arn, "") : try(data.aws_lb_listener.existing_http[0].arn, "")
  https_listener_arn = var.certificate_arn != "" ? (
    local.should_create_listeners ? try(aws_lb_listener.https[0].arn, "") : try(data.aws_lb_listener.existing_https[0].arn, "")
  ) : ""
  
  target_groups_map = merge(
    {
      for k, v in aws_lb_target_group.apis : k => v.arn
    },
    {
      for k, v in data.aws_lb_target_group.existing_apis : k => v.arn
      if !contains(keys(aws_lb_target_group.apis), k)
    }
  )
  
  primary_listener_arn = var.existing_listener_arn != "" ? var.existing_listener_arn : (
    var.certificate_arn != "" ? local.https_listener_arn : local.http_listener_arn
  )
}

resource "aws_lb_target_group" "frontend" {
  count            = local.should_create_frontend_tg ? 1 : 0
  name             = "${var.project_name}-frontend-tg"
  port     = var.services["front"].port
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = var.services["front"].health_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.project_name}-frontend-tg"
  }
}

data "aws_lb_target_group" "existing_frontend" {
  count = local.frontend_tg_exists ? 1 : 0
  name  = "${var.project_name}-frontend-tg"
}

data "aws_lb_target_group" "existing_apis" {
  for_each = local.existing_api_tg_set
  name     = "${var.project_name}-${each.key}-tg"
}

resource "aws_lb_target_group" "apis" {
  for_each = local.api_tgs_to_create
  name     = "kavoo-${each.key}-tg"
  port     = var.services[each.key].port  
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = var.services[each.key].health_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.project_name}-${each.key}-tg"
  }
}

resource "aws_lb_listener" "main" {
  count = local.should_create_listeners ? 1 : 0
  
  load_balancer_arn = local.alb_arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = var.certificate_arn != "" ? "redirect" : "forward"
    
    dynamic "redirect" {
      for_each = var.certificate_arn != "" ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "forward" {
      for_each = var.certificate_arn == "" ? [1] : []
      content {
        target_group {
          arn = var.create_target_groups ? aws_lb_target_group.frontend[0].arn : data.aws_lb_target_group.existing_frontend[0].arn
        }
      }
    }
  }

  tags = {
    Name = "${var.project_name}-http-listener"
  }
}

resource "aws_lb_listener" "https" {
  count = var.certificate_arn != "" && local.should_create_listeners ? 1 : 0
  
  load_balancer_arn = local.alb_arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "forward"
    
    forward {
      target_group {
        arn = var.create_target_groups ? aws_lb_target_group.frontend[0].arn : data.aws_lb_target_group.existing_frontend[0].arn
      }
    }
  }

  tags = {
    Name = "${var.project_name}-https-listener"
  }
}

resource "aws_lb_listener_rule" "api_routing" {
  for_each = local.api_rules_to_create
  
  listener_arn = local.primary_listener_arn
  priority     = var.services[each.key].priority

  action {
    type = "forward"
    
    forward {
      target_group {
        arn = local.target_groups_map[each.key]
      }
    }
  }

  condition {
    path_pattern {
      values = ["/api/${each.key}/*"]
    }
  }

  tags = {
    Name = "${var.project_name}-${each.key}-rule"
  }
}

resource "aws_route53_record" "main" {
  count = var.hosted_zone_id != "" ? 1 : 0
  
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = local.alb_dns_name
    zone_id                = local.alb_zone_id
    evaluate_target_health = true
  }
}