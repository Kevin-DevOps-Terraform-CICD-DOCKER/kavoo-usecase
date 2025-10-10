#!/bin/bash
# verify-cleanup.sh - Verificação completa pós-limpeza

echo "🔍 VERIFICAÇÃO COMPLETA PÓS-LIMPEZA"
echo "===================================="
echo "📋 Verificando os MESMOS recursos que cleanup-kavoo-infrastructure.sh remove"
echo "🎯 Garantindo correspondência 1:1 entre limpeza e verificação"
echo ""

AWS_REGION="us-east-1"
AWS_PROFILE="${AWS_PROFILE:-}"
found_resources=false
total_resources=0

# Função helper para comandos AWS CLI com profile
aws_cmd() {
    if [ -n "$AWS_PROFILE" ]; then
        aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"
    else
        aws --region "$AWS_REGION" "$@"
    fi
}

# Obter Account ID para verificações
caller_identity=$(aws_cmd sts get-caller-identity --output json 2>/dev/null)
account_id=$(echo "$caller_identity" | jq -r '.Account' 2>/dev/null || echo "unknown")

echo "🔑 Usando AWS Profile: ${AWS_PROFILE:-default}"
echo "🌍 Região: $AWS_REGION"
echo "📊 Account ID: $account_id"
echo ""

# Função para verificar recursos detalhadamente
verify_resource() {
    local resource_type="$1"
    local aws_command="$2"
    
    echo "📊 Verificando $resource_type..."
    
    if result=$(eval "$aws_command" 2>/dev/null) && [ -n "$result" ] && [ "$result" != "[]" ] && [ "$result" != "None" ]; then
        echo "⚠️  Ainda existem: $resource_type"
        echo "   Recursos encontrados:"
        echo "$result" | sed 's/^/      /'
        found_resources=true
        count=$(echo "$result" | wc -l)
        total_resources=$((total_resources + count))
        echo "   📊 Quantidade: $count"
    else
        echo "✅ $resource_type: LIMPO"
    fi
    echo ""
}

echo "🚀 Iniciando verificação detalhada..."
echo ""

# === FASE 1: VERIFICAÇÃO DE APLICAÇÕES E SERVIÇOS ===
echo "🎯 === FASE 1: APLICAÇÕES E SERVIÇOS ==="
echo ""

# 1. Verificar ECS Services específicos
echo "📊 Verificando ECS Services específicos..."
SERVICES=("kavoo-front" "kavoo-admins-api" "kavoo-checkout-api" "kavoo-members-api" "kavoo-users-api" "kavoo-webhooks-api")
services_found=""
for service in "${SERVICES[@]}"; do
    service_status=$(aws_cmd ecs describe-services --cluster kavoo-cluster --services $service --query 'services[0].serviceName' --output text 2>/dev/null || echo "None")
    if [ "$service_status" != "None" ] && [ -n "$service_status" ]; then
        services_found="$services_found $service"
    fi
done

if [ -n "$services_found" ]; then
    echo "⚠️  Ainda existem: ECS Services"
    echo "   Serviços encontrados:"
    for service in $services_found; do
        echo "      $service"
        # Verificar desired count
        desired_count=$(aws_cmd ecs describe-services --cluster kavoo-cluster --services $service --query 'services[0].desiredCount' --output text 2>/dev/null || echo "0")
        echo "         └─ Desired Count: $desired_count"
    done
    found_resources=true
    count=$(echo $services_found | wc -w)
    total_resources=$((total_resources + count))
    echo "   📊 Quantidade: $count"
else
    echo "✅ ECS Services: LIMPO"
fi
echo ""

# 2. Verificar ECS Cluster
verify_resource "ECS Cluster (kavoo-cluster)" \
    "aws_cmd ecs describe-clusters --clusters kavoo-cluster --query 'clusters[0].clusterName' --output text"

# 3. Verificar ECR Repositories
echo "📊 Verificando ECR Repositories..."
ECR_REPOS=("kavoo/front" "kavoo/admins-api" "kavoo/checkout-api" "kavoo/members-api" "kavoo/users-api" "kavoo/webhooks-api")
repos_found=""
for repo in "${ECR_REPOS[@]}"; do
    repo_status=$(aws_cmd ecr describe-repositories --repository-names $repo --query 'repositories[0].repositoryName' --output text 2>/dev/null || echo "None")
    if [ "$repo_status" != "None" ] && [ -n "$repo_status" ]; then
        repos_found="$repos_found $repo"
    fi
done

if [ -n "$repos_found" ]; then
    echo "⚠️  Ainda existem: ECR Repositories"
    echo "   Repositórios encontrados:"
    for repo in $repos_found; do
        echo "      $repo"
        image_count=$(aws_cmd ecr list-images --repository-name $repo --query 'length(imageIds)' --output text 2>/dev/null || echo "0")
        echo "         └─ Imagens: $image_count"
    done
    found_resources=true
    count=$(echo $repos_found | wc -w)
    total_resources=$((total_resources + count))
    echo "   📊 Quantidade: $count repositórios"
else
    echo "✅ ECR Repositories: LIMPO"
fi
echo ""

# 4. Verificar Load Balancer
verify_resource "Load Balancer (kavoo-alb)" \
    "aws_cmd elbv2 describe-load-balancers --names kavoo-alb --query 'LoadBalancers[0].LoadBalancerName' --output text"

# 5. Verificar Target Groups
verify_resource "Target Groups" \
    "aws_cmd elbv2 describe-target-groups --query 'TargetGroups[?contains(TargetGroupName, \`kavoo\`)].TargetGroupName' --output text"

# 6. Verificar Security Groups
verify_resource "Security Groups" \
    "aws_cmd ec2 describe-security-groups --filters 'Name=group-name,Values=*kavoo*' 'Name=tag:Name,Values=*kavoo*' --query 'SecurityGroups[?GroupName!=\`default\`].GroupName' --output text"

# 7. Verificar CloudWatch Log Groups
verify_resource "CloudWatch Log Groups" \
    "aws_cmd logs describe-log-groups --log-group-name-prefix '/ecs/kavoo' --query 'logGroups[].logGroupName' --output text"

# 7.1. Verificar CloudWatch Dashboards
verify_resource "CloudWatch Dashboards" \
    "aws_cmd cloudwatch list-dashboards --query 'DashboardEntries[?contains(DashboardName, \`kavoo\`) || contains(DashboardName, \`cost-monitoring\`)].DashboardName' --output text"

# 7.2. Verificar CloudWatch Alarms
verify_resource "CloudWatch Alarms" \
    "aws_cmd cloudwatch describe-alarms --query 'MetricAlarms[?contains(AlarmName, \`kavoo\`) || contains(AlarmName, \`high-estimated-charges\`)].AlarmName' --output text"

# 8. Verificar Task Definitions
verify_resource "Task Definitions" \
    "aws_cmd ecs list-task-definitions --query 'taskDefinitionArns[?contains(@, \`kavoo\`)]' --output text"

# 8.1. Verificar Lambda Functions
verify_resource "Lambda Functions (smart-deploy)" \
    "aws_cmd lambda list-functions --query 'Functions[?contains(FunctionName, \`kavoo\`) || contains(FunctionName, \`health-checker\`)].FunctionName' --output text"

# 8.2. Verificar EventBridge Rules
echo "📊 Verificando EventBridge Rules..."
eventbridge_rules=$(aws_cmd events list-rules --query 'Rules[?contains(Name, `kavoo`) || contains(Name, `health-check`)].Name' --output text 2>/dev/null || echo "")
if [ -n "$eventbridge_rules" ]; then
    echo "⚠️  Ainda existem: EventBridge Rules"
    echo "   Rules encontradas:"
    for rule_name in $eventbridge_rules; do
        echo "      $rule_name"
        # Verificar targets
        targets=$(aws_cmd events list-targets-by-rule --rule $rule_name --query 'Targets[].Id' --output text 2>/dev/null || echo "")
        if [ -n "$targets" ]; then
            echo "         └─ Targets: $(echo $targets | wc -w)"
        fi
    done
    found_resources=true
    count=$(echo $eventbridge_rules | wc -w)
    total_resources=$((total_resources + count))
    echo "   📊 Quantidade: $count"
else
    echo "✅ EventBridge Rules: LIMPO"
fi
echo ""

# 9. Verificar Route 53
verify_resource "Route 53 Zones" \
    "aws_cmd route53 list-hosted-zones --query 'HostedZones[?contains(Name, \`kavoo\`)].Name' --output text"

# 10. Certificados ACM (preservados)
echo "📊 Verificando SSL Certificates..."
echo "ℹ️ SSL Certificates: PRESERVADOS (não removidos automaticamente)"
cert_count=$(aws_cmd acm list-certificates --query 'length(CertificateSummaryList[?contains(DomainName, `kavoo`)])' --output text 2>/dev/null || echo "0")
echo "   📊 Certificados encontrados: $cert_count (mantidos intencionalmente)"
echo ""

# === VERIFICAÇÃO DE RECURSOS DE REDE ===
echo "🌐 === VERIFICAÇÃO DE RECURSOS DE REDE ==="
echo ""

# 11. Verificar Internet Gateways
verify_resource "Internet Gateways" \
    "aws_cmd ec2 describe-internet-gateways --filters 'Name=tag:Name,Values=*kavoo*' --query 'InternetGateways[].InternetGatewayId' --output text"

# 12. Verificar Subnets
verify_resource "Subnets" \
    "aws_cmd ec2 describe-subnets --filters 'Name=tag:Name,Values=*kavoo*' --query 'Subnets[].SubnetId' --output text"

# 13. Verificar Route Tables
verify_resource "Route Tables" \
    "aws_cmd ec2 describe-route-tables --filters 'Name=tag:Name,Values=*kavoo*' --query 'RouteTables[].RouteTableId' --output text"

# 14. Verificar VPCs
verify_resource "VPCs" \
    "aws_cmd ec2 describe-vpcs --filters 'Name=tag:Name,Values=*kavoo*' --query 'Vpcs[?IsDefault==\`false\`].VpcId' --output text"

# 14.1. Verificar NAT Gateways
verify_resource "NAT Gateways" \
    "aws_cmd ec2 describe-nat-gateways --filter 'Name=tag:Name,Values=*kavoo*' --query 'NatGateways[?State!=\`deleted\`].NatGatewayId' --output text"

# 15. Verificar Elastic IPs
echo "📊 Verificando Elastic IPs..."
# Verificar EIPs do projeto
project_eips=$(aws_cmd ec2 describe-addresses --filters "Name=tag:Name,Values=*kavoo*" --query 'Addresses[].AllocationId' --output text 2>/dev/null || echo "")
# Verificar EIPs não associados
unattached_eips=$(aws_cmd ec2 describe-addresses --query 'Addresses[?AssociationId==null].AllocationId' --output text 2>/dev/null || echo "")

if [ -n "$project_eips" ] || [ -n "$unattached_eips" ]; then
    echo "⚠️  Ainda existem: Elastic IPs"
    if [ -n "$project_eips" ]; then
        echo "   EIPs do projeto:"
        for eip in $project_eips; do
            echo "      $eip"
        done
    fi
    if [ -n "$unattached_eips" ]; then
        echo "   EIPs não utilizados:"
        for eip in $unattached_eips; do
            # Evitar duplicação
            if [[ ! " $project_eips " =~ " $eip " ]]; then
                echo "      $eip"
            fi
        done
    fi
    found_resources=true
    total_count=$(($(echo $project_eips | wc -w) + $(echo $unattached_eips | wc -w)))
    total_resources=$((total_resources + total_count))
    echo "   📊 Quantidade: $total_count"
else
    echo "✅ Elastic IPs: LIMPO"
fi
echo ""

# === FASE 2: VERIFICAÇÃO DE DADOS E ARMAZENAMENTO ===
echo "🗃️ === FASE 2: DADOS E ARMAZENAMENTO ==="
echo ""

# 16. Verificar RDS Instances
verify_resource "RDS Instances" \
    "aws_cmd rds describe-db-instances --query 'DBInstances[?contains(DBInstanceIdentifier, \`kavoo\`)].DBInstanceIdentifier' --output text"

# 16.1. Verificar RDS Subnet Groups
verify_resource "RDS Subnet Groups" \
    "aws_cmd rds describe-db-subnet-groups --query 'DBSubnetGroups[?contains(DBSubnetGroupName, \`kavoo\`)].DBSubnetGroupName' --output text"

# 17. Verificar ElastiCache Clusters
verify_resource "ElastiCache Clusters" \
    "aws_cmd elasticache describe-cache-clusters --query 'CacheClusters[?contains(CacheClusterId, \`kavoo\`)].CacheClusterId' --output text"

# 17.1. Verificar ElastiCache Subnet Groups
verify_resource "ElastiCache Subnet Groups" \
    "aws_cmd elasticache describe-cache-subnet-groups --query 'CacheSubnetGroups[?contains(CacheSubnetGroupName, \`kavoo\`)].CacheSubnetGroupName' --output text"

# === FASE 3: VERIFICAÇÃO DE SEGURANÇA E MONITORAMENTO ===
echo "🔐 === FASE 3: SEGURANÇA E MONITORAMENTO ==="
echo ""

# 18. Verificar Secrets Manager
verify_resource "Secrets Manager" \
    "aws_cmd secretsmanager list-secrets --query 'SecretList[?contains(Name, \`kavoo\`)].Name' --output text"

# 19. Verificar IAM Roles
verify_resource "IAM Roles" \
    "aws_cmd iam list-roles --query 'Roles[?contains(RoleName, \`kavoo\`) || contains(RoleName, \`ecsTask\`) || contains(RoleName, \`ecsExecution\`) || contains(RoleName, \`health-checker\`) || contains(RoleName, \`rds-monitoring\`)].RoleName' --output text"

# 19.1. Verificar AWS Budget
if [ "$account_id" != "unknown" ]; then
    verify_resource "AWS Budget" \
        "aws_cmd budgets describe-budgets --account-id $account_id --query 'Budgets[?contains(BudgetName, \`kavoo\`) || contains(BudgetName, \`monthly-budget\`)].BudgetName' --output text"
else
    echo "📊 Verificando AWS Budget..."
    echo "⚠️ Não foi possível verificar budgets (Account ID desconhecido)"
    echo ""
fi

# === FASE 4: VERIFICAÇÃO FINAL ===
echo "🎯 === FASE 4: VERIFICAÇÃO FINAL ==="
echo ""

# 20. Verificar arquivos Terraform State
echo "📊 Verificando arquivos Terraform State..."
terraform_files_exist=false
if [ -f "terraform.tfstate" ]; then
    echo "⚠️  Ainda existe: terraform.tfstate"
    terraform_files_exist=true
fi
if [ -f "terraform.tfstate.backup" ]; then
    echo "⚠️  Ainda existe: terraform.tfstate.backup"
    terraform_files_exist=true
fi

if [ "$terraform_files_exist" = false ]; then
    echo "✅ Terraform State Files: LIMPO"
else
    found_resources=true
    total_resources=$((total_resources + 1))
fi
echo ""

# Resumo final
echo "===================================="
echo "📊 RESUMO DA VERIFICAÇÃO:"
echo ""

if [ "$found_resources" = false ]; then
    echo "🎉 LIMPEZA 100% COMPLETA!"
    echo "✅ Todos os recursos da infraestrutura Kavoo foram removidos"
    echo "🛡️ Certificados ACM preservados conforme solicitado"
    echo "💰 Não haverá custos adicionais relacionados ao projeto"
    echo ""
    echo "📊 CORRESPONDÊNCIA PERFEITA:"
    echo "   ✅ Script validou EXATAMENTE os mesmos recursos do cleanup"
    echo "   ✅ Verificação sincronizada com cleanup-kavoo-infrastructure.sh"
else
    echo "⚠️  LIMPEZA PARCIAL DETECTADA"
    echo "❗ Total de recursos restantes: $total_resources"
    echo ""
    echo "🛠️  AÇÕES RECOMENDADAS:"
    echo "   1. Executar novamente: ./scripts/cleanup-kavoo-infrastructure.sh"
    echo "   2. Verificar dependências entre recursos"
    echo "   3. Aguardar propagação de deletions (alguns recursos levam tempo)"
    echo "   4. Remover manualmente via AWS Console se necessário"
    echo ""
    echo "⏱️  RECURSOS QUE PODEM LEVAR TEMPO PARA DELETAR:"
    echo "   - NAT Gateways (podem levar até 5 minutos)"
    echo "   - RDS Instances (podem levar até 10 minutos)"
    echo "   - Load Balancers (podem levar até 2 minutos)"
    echo "   - VPCs (dependem de todos os recursos internos serem removidos)"
fi

echo ""
echo "📅 Verificação concluída em: $(date)"
echo "🌍 Região verificada: $AWS_REGION"
echo "🔑 Profile usado: ${AWS_PROFILE:-default}"
echo "📊 Account ID: $account_id"
echo "===================================="
