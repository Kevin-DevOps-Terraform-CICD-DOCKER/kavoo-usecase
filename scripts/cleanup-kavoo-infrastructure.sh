#!/bin/bash
# cleanup-kavoo-infrastructure.sh
set -e
echo "🔥 KAVOO INFRASTRUCTURE CLEANUP SCRIPT"
echo "======================================"
echo "⚠️  ATENÇÃO: Este script vai DELETAR TODA a infraestrutura AWS!"
echo "📋 Recursos que serão removidos:"
echo "   - ECS Cluster, Services e Task Definitions"
echo "   - ECR Repositories e Imagens" 
echo "   - Application Load Balancer e Target Groups"
echo "   - Security Groups personalizados"
echo "   - CloudWatch Log Groups, Dashboards e Alarms"
echo "   - Lambda Functions (smart-deploy health checker)"
echo "   - EventBridge Rules e Targets"
echo "   - Route 53 Records (se existirem)"
echo "   - VPC, Subnets, IGW, Route Tables e NAT Gateways"
echo "   - RDS Instances e DB Subnet Groups"
echo "   - ElastiCache Clusters e Cache Subnet Groups"
echo "   - Secrets Manager Secrets"
echo "   - AWS Budgets (monitoramento de custos)"
echo "   - Elastic IPs não utilizados"
echo ""
echo "🛡️ Recursos preservados:"
echo "   - Certificados ACM (remoção manual se necessário)"
echo "   - IAM Roles (preservadas por segurança - remoção manual se necessário)"
echo ""
read -p "🤔 Tem certeza que deseja continuar? (digite 'DELETE' para confirmar): " confirmation
if [ "$confirmation" != "DELETE" ]; then
    echo "❌ Operação cancelada."
    exit 1
fi
# Configurações
AWS_PROFILE="${AWS_PROFILE:-}"
AWS_REGION="us-east-1"
CLUSTER_NAME="kavoo-cluster"
ECR_REPOS=("kavoo/front" "kavoo/admins-api" "kavoo/checkout-api" "kavoo/members-api" "kavoo/users-api" "kavoo/webhooks-api")
SERVICES=("kavoo-front" "kavoo-admins-api" "kavoo-checkout-api" "kavoo-members-api" "kavoo-users-api" "kavoo-webhooks-api")

# Lista ampliada de padrões para busca de recursos
RESOURCE_PATTERNS=("kavoo" "kavoo-*" "*kavoo*")

# Função para log com timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Função helper para comandos AWS CLI com profile
aws_cmd() {
    if [ -n "$AWS_PROFILE" ]; then
        aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"
    else
        aws --region "$AWS_REGION" "$@"
    fi
}

echo "🔑 Usando AWS Profile: ${AWS_PROFILE:-default}"
echo "🌍 Região: $AWS_REGION"

# Teste de conectividade AWS
log "🔍 Testando conectividade AWS..."
if ! aws_cmd sts get-caller-identity >/dev/null 2>&1; then
    echo "❌ ERRO: Não foi possível conectar à AWS com o profile '$AWS_PROFILE'"
    echo "   Verifique suas credenciais e permissões"
    exit 1
fi

caller_identity=$(aws_cmd sts get-caller-identity --output json 2>/dev/null)
account_id=$(echo "$caller_identity" | jq -r '.Account' 2>/dev/null || echo "unknown")
user_arn=$(echo "$caller_identity" | jq -r '.Arn' 2>/dev/null || echo "unknown")

echo "✅ Conectado com sucesso!"
echo "   Account ID: $account_id"
echo "   User/Role: $user_arn"

echo ""
echo "🚀 Iniciando limpeza..."
echo ""
# === FASE 1: LIMPEZA DE APLICAÇÕES E SERVIÇOS ===
# 1. Parar todos os serviços ECS
log "🛑 Parando serviços ECS..."
for service in "${SERVICES[@]}"; do
    log "   Parando $service..."
    aws_cmd ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $service \
        --desired-count 0 > /dev/null 2>&1 || log "   ⚠️ Serviço $service não encontrado"
done
# Aguardar serviços pararem
log "⏳ Aguardando serviços pararem (30s)..."
sleep 30
# 2. Deletar serviços ECS
log "🗑️ Deletando serviços ECS..."
for service in "${SERVICES[@]}"; do
    log "   Deletando $service..."
    aws_cmd ecs delete-service \
        --cluster $CLUSTER_NAME \
        --service $service > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar $service"
done
# 3. Deletar cluster ECS
log "🗑️ Deletando cluster ECS..."
aws_cmd ecs delete-cluster \
    --cluster $CLUSTER_NAME \
 \
     > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar cluster"
# 4. Deletar imagens e repositórios ECR
log "🗑️ Limpando repositórios ECR..."
for repo in "${ECR_REPOS[@]}"; do
    log "   Processando repositório $repo..."
    # Deletar todas as imagens
    images=$(aws_cmd ecr list-images --repository-name $repo \
        --query 'imageIds[*]' --output json 2>/dev/null || echo "[]")
    if [ "$images" != "[]" ] && [ -n "$images" ]; then
        echo "$images" > /tmp/images_${repo//\//_}.json
        aws_cmd ecr batch-delete-image \
            --repository-name $repo \
            --image-ids file:///tmp/images_${repo//\//_}.json > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar imagens de $repo"
        rm -f /tmp/images_${repo//\//_}.json
    fi
    # Deletar repositório
    aws_cmd ecr delete-repository \
        --repository-name $repo > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar repositório $repo"
done
# 5. Deletar Load Balancer
log "🗑️ Deletando Application Load Balancer..."
alb_arn=$(aws_cmd elbv2 describe-load-balancers \
    --names kavoo-alb \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text 2>/dev/null || echo "None")
if [ "$alb_arn" != "None" ] && [ "$alb_arn" != "" ]; then
    aws_cmd elbv2 delete-load-balancer \
        --load-balancer-arn $alb_arn > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar ALB"
else
    log "   ℹ️ ALB não encontrado"
fi
# 6. Deletar Target Groups
log "🗑️ Deletando Target Groups..."
target_groups=$(aws_cmd elbv2 describe-target-groups \
    --query 'TargetGroups[?contains(TargetGroupName, `kavoo`)].TargetGroupArn' \
    --output text 2>/dev/null || echo "")
if [ -n "$target_groups" ]; then
    for tg_arn in $target_groups; do
        aws_cmd elbv2 delete-target-group \
            --target-group-arn $tg_arn > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar target group"
    done
else
    log "   ℹ️ Nenhum target group encontrado"
fi
# Aguardar ALB ser totalmente removido antes de continuar
log "⏳ Aguardando ALB ser totalmente removido (60s)..."
sleep 60
# 7. Deletar Security Groups
log "🗑️ Deletando Security Groups..."
security_groups=$(aws_cmd ec2 describe-security-groups \
    --filters "Name=group-name,Values=*kavoo*" "Name=tag:Name,Values=*kavoo*" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
    --output text 2>/dev/null || echo "")
if [ -n "$security_groups" ]; then
    for sg_id in $security_groups; do
        aws_cmd ec2 delete-security-group \
            --group-id $sg_id \
             > /dev/null 2>&1 || log "   ⚠️ Security group $sg_id pode estar em uso"
    done
else
    log "   ℹ️ Nenhum security group encontrado"
fi
# 8. Deletar CloudWatch Log Groups
log "🗑️ Deletando CloudWatch Log Groups..."
log_groups=$(aws_cmd logs describe-log-groups \
    --log-group-name-prefix "/ecs/kavoo" \
    --query 'logGroups[].logGroupName' \
    --output text 2>/dev/null || echo "")
if [ -n "$log_groups" ]; then
    for log_group in $log_groups; do
        log "   Deletando log group: $log_group"
        aws_cmd logs delete-log-group \
            --log-group-name $log_group > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar log group $log_group"
    done
else
    log "   ℹ️ Nenhum log group encontrado"
fi

# 8.1. Deletar CloudWatch Dashboards
log "🗑️ Deletando CloudWatch Dashboards..."
dashboards=$(aws_cmd cloudwatch list-dashboards \
    --query 'DashboardEntries[?contains(DashboardName, `kavoo`) || contains(DashboardName, `cost-monitoring`)].DashboardName' \
    --output text 2>/dev/null || echo "")
if [ -n "$dashboards" ]; then
    for dashboard_name in $dashboards; do
        log "   Deletando dashboard: $dashboard_name"
        aws_cmd cloudwatch delete-dashboards \
            --dashboard-names $dashboard_name > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar dashboard $dashboard_name"
    done
else
    log "   ℹ️ Nenhum dashboard encontrado"
fi

# 8.2. Deletar CloudWatch Alarms
log "🗑️ Deletando CloudWatch Alarms..."
alarms=$(aws_cmd cloudwatch describe-alarms \
    --query 'MetricAlarms[?contains(AlarmName, `kavoo`) || contains(AlarmName, `high-estimated-charges`)].AlarmName' \
    --output text 2>/dev/null || echo "")
if [ -n "$alarms" ]; then
    for alarm_name in $alarms; do
        log "   Deletando alarm: $alarm_name"
        aws_cmd cloudwatch delete-alarms \
            --alarm-names $alarm_name > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar alarm $alarm_name"
    done
else
    log "   ℹ️ Nenhum alarm encontrado"
fi
# 9. Deletar Task Definitions
log "🗑️ Deletando Task Definitions..."
task_definitions=$(aws_cmd ecs list-task-definitions \
 \
    --query 'taskDefinitionArns[?contains(@, `kavoo`)]' \
    --output text 2>/dev/null || echo "")
if [ -n "$task_definitions" ]; then
    for task_def in $task_definitions; do
        aws_cmd ecs deregister-task-definition \
            --task-definition $task_def \
             > /dev/null 2>&1 || log "   ⚠️ Erro ao desregistrar task definition $task_def"
    done
else
    log "   ℹ️ Nenhuma task definition encontrada"
fi

# 9.1. Deletar Lambda Functions (smart-deploy health checker)
log "🗑️ Deletando Lambda Functions..."
lambda_functions=$(aws_cmd lambda list-functions \
    --query 'Functions[?contains(FunctionName, `kavoo`) || contains(FunctionName, `health-checker`)].FunctionName' \
    --output text 2>/dev/null || echo "")
if [ -n "$lambda_functions" ]; then
    for func_name in $lambda_functions; do
        log "   Deletando Lambda function: $func_name"
        aws_cmd lambda delete-function \
            --function-name $func_name > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar Lambda function $func_name"
    done
else
    log "   ℹ️ Nenhuma Lambda function encontrada"
fi

# 9.2. Deletar EventBridge Rules e Targets
log "🗑️ Deletando EventBridge Rules..."
eventbridge_rules=$(aws_cmd events list-rules \
    --query 'Rules[?contains(Name, `kavoo`) || contains(Name, `health-check`)].Name' \
    --output text 2>/dev/null || echo "")
if [ -n "$eventbridge_rules" ]; then
    for rule_name in $eventbridge_rules; do
        log "   Processando EventBridge rule: $rule_name"
        
        # Remover targets primeiro
        targets=$(aws_cmd events list-targets-by-rule \
            --rule $rule_name \
            --query 'Targets[].Id' \
            --output text 2>/dev/null || echo "")
        if [ -n "$targets" ]; then
            for target_id in $targets; do
                aws_cmd events remove-targets \
                    --rule $rule_name \
                    --ids $target_id > /dev/null 2>&1 || log "   ⚠️ Erro ao remover target $target_id"
            done
        fi
        
        # Deletar a regra
        aws_cmd events delete-rule \
            --name $rule_name > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar EventBridge rule $rule_name"
    done
else
    log "   ℹ️ Nenhuma EventBridge rule encontrada"
fi
# 10. Deletar Route 53 Records (se existirem)
log "🗑️ Verificando Route 53 Records..."
hosted_zones=$(aws_cmd route53 list-hosted-zones \
    --query 'HostedZones[?contains(Name, `kavoo`)].Id' \
    --output text 2>/dev/null || echo "")
if [ -n "$hosted_zones" ]; then
    for zone_id in $hosted_zones; do
        zone_id_clean=${zone_id##*/}
        log "   Processando zona: $zone_id_clean"
        # Obter todos os records exceto NS e SOA
        records=$(aws_cmd route53 list-resource-record-sets \
            --hosted-zone-id $zone_id_clean \
 \
            --query 'ResourceRecordSets[?Type!=`NS` && Type!=`SOA`]' \
            --output json 2>/dev/null || echo "[]")
        if [ "$records" != "[]" ] && [ -n "$records" ]; then
            echo "$records" > /tmp/records_$zone_id_clean.json
            # Processar cada record individualmente
            echo "$records" | jq -c '.[]' | while read -r record; do
                record_name=$(echo "$record" | jq -r '.Name')
                record_type=$(echo "$record" | jq -r '.Type')
                change_batch=$(cat <<EOF
{
  "Changes": [
    {
      "Action": "DELETE",
      "ResourceRecordSet": $record
    }
  ]
}
EOF
)
                echo "$change_batch" > /tmp/change_batch_${zone_id_clean}_$(echo "$record_name" | tr '.' '_').json
                aws_cmd route53 change-resource-record-sets \
                    --hosted-zone-id $zone_id_clean \
                    --change-batch file:///tmp/change_batch_${zone_id_clean}_$(echo "$record_name" | tr '.' '_').json \
                     > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar record $record_name ($record_type)"
                rm -f /tmp/change_batch_${zone_id_clean}_$(echo "$record_name" | tr '.' '_').json
            done
            rm -f /tmp/records_$zone_id_clean.json
        fi
    done
else
    log "   ℹ️ Nenhuma hosted zone encontrada"
fi
# 11. Certificados ACM são preservados (não deletados automaticamente)
log "ℹ️ Certificados ACM serão preservados (remoção manual se necessário)"
# 11.1. IAM Roles são preservadas (não deletadas automaticamente por segurança)
log "ℹ️ IAM Roles serão preservadas por segurança (remoção manual se necessário)"
# === LIMPEZA DE RECURSOS DE REDE ===
# 12. Deletar Internet Gateway personalizado (se existir)
log "🗑️ Verificando Internet Gateway personalizado..."
custom_igw=$(aws_cmd ec2 describe-internet-gateways \
 \
    --filters "Name=tag:Name,Values=*kavoo*" \
    --query 'InternetGateways[].InternetGatewayId' \
    --output text 2>/dev/null || echo "")
if [ -n "$custom_igw" ]; then
    for igw_id in $custom_igw; do
        # Desanexar da VPC primeiro
        vpc_id=$(aws_cmd ec2 describe-internet-gateways \
            --internet-gateway-ids $igw_id \
 \
            --query 'InternetGateways[0].Attachments[0].VpcId' \
            --output text 2>/dev/null || echo "")
        if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
            aws_cmd ec2 detach-internet-gateway \
                --internet-gateway-id $igw_id \
                --vpc-id $vpc_id \
                 > /dev/null 2>&1 || log "   ⚠️ Erro ao desanexar IGW $igw_id"
        fi
        aws_cmd ec2 delete-internet-gateway \
            --internet-gateway-id $igw_id \
             > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar IGW $igw_id"
    done
else
    log "   ℹ️ Nenhum Internet Gateway personalizado encontrado"
fi
# 13. Deletar Subnets personalizadas
log "🗑️ Deletando Subnets personalizadas..."
custom_subnets=$(aws_cmd ec2 describe-subnets \
 \
    --filters "Name=tag:Name,Values=*kavoo*" \
    --query 'Subnets[].SubnetId' \
    --output text 2>/dev/null || echo "")
if [ -n "$custom_subnets" ]; then
    for subnet_id in $custom_subnets; do
        aws_cmd ec2 delete-subnet \
            --subnet-id $subnet_id \
             > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar subnet $subnet_id"
    done
else
    log "   ℹ️ Nenhuma subnet personalizada encontrada"
fi
# 14. Deletar Route Tables personalizadas
log "🗑️ Deletando Route Tables personalizadas..."
custom_route_tables=$(aws_cmd ec2 describe-route-tables \
 \
    --filters "Name=tag:Name,Values=*kavoo*" \
    --query 'RouteTables[].RouteTableId' \
    --output text 2>/dev/null || echo "")
if [ -n "$custom_route_tables" ]; then
    for rt_id in $custom_route_tables; do
        aws_cmd ec2 delete-route-table \
            --route-table-id $rt_id \
             > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar route table $rt_id"
    done
else
    log "   ℹ️ Nenhuma route table personalizada encontrada"
fi
# 15. Deletar VPC personalizada
log "🗑️ Deletando VPC personalizada..."
custom_vpc=$(aws_cmd ec2 describe-vpcs \
 \
    --filters "Name=tag:Name,Values=*kavoo*" \
    --query 'Vpcs[?IsDefault==`false`].VpcId' \
    --output text 2>/dev/null || echo "")
if [ -n "$custom_vpc" ]; then
    for vpc_id in $custom_vpc; do
        aws_cmd ec2 delete-vpc \
            --vpc-id $vpc_id \
             > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar VPC $vpc_id"
    done
else
    log "   ℹ️ Nenhuma VPC personalizada encontrada"
fi
# 15.1. Deletar NAT Gateways personalizados
log "🗑️ Deletando NAT Gateways personalizados..."
custom_nat_gateways=$(aws_cmd ec2 describe-nat-gateways \
    --filter "Name=tag:Name,Values=*kavoo*" \
    --query 'NatGateways[?State!=`deleted`].NatGatewayId' \
    --output text 2>/dev/null || echo "")
if [ -n "$custom_nat_gateways" ]; then
    for nat_gw_id in $custom_nat_gateways; do
        log "   Deletando NAT Gateway: $nat_gw_id"
        aws_cmd ec2 delete-nat-gateway \
            --nat-gateway-id $nat_gw_id > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar NAT Gateway $nat_gw_id"
    done
    # Aguardar NAT Gateways serem deletados antes de liberar EIPs
    log "⏳ Aguardando NAT Gateways serem deletados (60s)..."
    sleep 60
else
    log "   ℹ️ Nenhum NAT Gateway personalizado encontrado"
fi

# 16. Deletar Elastic IPs (incluindo os do NAT Gateway)
log "🗑️ Verificando Elastic IPs relacionados ao projeto..."
# Primeiro, buscar EIPs com tags do projeto
project_eips=$(aws_cmd ec2 describe-addresses \
    --filters "Name=tag:Name,Values=*kavoo*" \
    --query 'Addresses[].AllocationId' \
    --output text 2>/dev/null || echo "")
if [ -n "$project_eips" ]; then
    for eip_id in $project_eips; do
        log "   Liberando EIP do projeto: $eip_id"
        aws_cmd ec2 release-address \
            --allocation-id $eip_id > /dev/null 2>&1 || log "   ⚠️ Erro ao liberar EIP $eip_id"
    done
fi

# Depois, buscar EIPs não associados (cleanup geral)
unattached_eips=$(aws_cmd ec2 describe-addresses \
    --query 'Addresses[?AssociationId==null].AllocationId' \
    --output text 2>/dev/null || echo "")
if [ -n "$unattached_eips" ]; then
    for eip_id in $unattached_eips; do
        # Verificar se não é um EIP já processado acima
        if [[ ! " $project_eips " =~ " $eip_id " ]]; then
            log "   Liberando EIP não utilizado: $eip_id"
            aws_cmd ec2 release-address \
                --allocation-id $eip_id > /dev/null 2>&1 || log "   ⚠️ Erro ao liberar EIP $eip_id"
        fi
    done
fi

if [ -z "$project_eips" ] && [ -z "$unattached_eips" ]; then
    log "   ℹ️ Nenhum Elastic IP encontrado para liberação"
fi
# === FASE 2: LIMPEZA DE DADOS E ARMAZENAMENTO ===
# 17. Deletar RDS Instances e Subnet Groups (se existirem)
log "🗑️ Verificando RDS Instances..."
rds_instances=$(aws_cmd rds describe-db-instances \
 \
    --query 'DBInstances[?contains(DBInstanceIdentifier, `kavoo`)].DBInstanceIdentifier' \
    --output text 2>/dev/null || echo "")
if [ -n "$rds_instances" ]; then
    for db_instance in $rds_instances; do
        log "   Deletando RDS instance: $db_instance"
        aws_cmd rds delete-db-instance \
            --db-instance-identifier $db_instance \
            --skip-final-snapshot \
            --delete-automated-backups \
             > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar RDS instance $db_instance"
    done
    # Aguardar instances serem removidas
    log "⏳ Aguardando RDS instances serem removidas (120s)..."
    sleep 120
else
    log "   ℹ️ Nenhuma RDS instance encontrada"
fi
# Deletar DB Subnet Groups
log "🗑️ Deletando DB Subnet Groups..."
rds_subnet_groups=$(aws_cmd rds describe-db-subnet-groups \
    --query 'DBSubnetGroups[?contains(DBSubnetGroupName, `kavoo`)].DBSubnetGroupName' \
    --output text 2>/dev/null || echo "")
if [ -n "$rds_subnet_groups" ]; then
    for subnet_group in $rds_subnet_groups; do
        log "   Deletando DB subnet group: $subnet_group"
        aws_cmd rds delete-db-subnet-group \
            --db-subnet-group-name $subnet_group > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar DB subnet group $subnet_group"
    done
else
    log "   ℹ️ Nenhum DB subnet group encontrado"
fi
# 18. Deletar ElastiCache Clusters e Subnet Groups (se existirem)
log "🗑️ Verificando ElastiCache Clusters..."
cache_clusters=$(aws_cmd elasticache describe-cache-clusters \
 \
    --query 'CacheClusters[?contains(CacheClusterId, `kavoo`)].CacheClusterId' \
    --output text 2>/dev/null || echo "")
if [ -n "$cache_clusters" ]; then
    for cache_cluster in $cache_clusters; do
        aws_cmd elasticache delete-cache-cluster \
            --cache-cluster-id $cache_cluster \
             > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar cache cluster $cache_cluster"
    done
    # Aguardar clusters serem removidos
    log "⏳ Aguardando cache clusters serem removidos (60s)..."
    sleep 60
else
    log "   ℹ️ Nenhum cache cluster encontrado"
fi
# Deletar Cache Subnet Groups
log "🗑️ Deletando Cache Subnet Groups..."
cache_subnet_groups=$(aws_cmd elasticache describe-cache-subnet-groups \
    --query 'CacheSubnetGroups[?contains(CacheSubnetGroupName, `kavoo`)].CacheSubnetGroupName' \
    --output text 2>/dev/null || echo "")
if [ -n "$cache_subnet_groups" ]; then
    for cache_subnet_group in $cache_subnet_groups; do
        log "   Deletando cache subnet group: $cache_subnet_group"
        aws_cmd elasticache delete-cache-subnet-group \
            --cache-subnet-group-name $cache_subnet_group > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar cache subnet group $cache_subnet_group"
    done
else
    log "   ℹ️ Nenhum cache subnet group encontrado"
fi
# === FASE 3: LIMPEZA DE SEGURANÇA E MONITORAMENTO ===
# 19. Deletar Secrets Manager Secrets
log "🗑️ Deletando Secrets Manager Secrets..."
secrets=$(aws_cmd secretsmanager list-secrets \
 \
    --query 'SecretList[?contains(Name, `kavoo`)].ARN' \
    --output text 2>/dev/null || echo "")
if [ -n "$secrets" ]; then
    for secret_arn in $secrets; do
        aws_cmd secretsmanager delete-secret \
            --secret-id $secret_arn \
            --force-delete-without-recovery \
             > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar secret $secret_arn"
    done
else
    log "   ℹ️ Nenhum secret encontrado"
fi
# 20. IAM Roles são preservadas por segurança (não deletadas automaticamente)
log "�️ Verificando IAM Roles relacionadas (preservadas por segurança)..."
iam_roles=$(aws_cmd iam list-roles \
    --query 'Roles[?contains(RoleName, `kavoo`) || contains(RoleName, `ecsTask`) || contains(RoleName, `ecsExecution`) || contains(RoleName, `health-checker`) || contains(RoleName, `rds-monitoring`)].RoleName' \
    --output text 2>/dev/null || echo "")
if [ -n "$iam_roles" ]; then
    log "   ℹ️ IAM Roles encontradas (PRESERVADAS):"
    for role_name in $iam_roles; do
        log "      - $role_name"
    done
    log "   🛡️ SEGURANÇA: IAM Roles mantidas para evitar problemas de acesso"
    log "   📋 Para remoção manual: Console IAM → Roles → Delete individual"
else
    log "   ℹ️ Nenhuma IAM role relacionada encontrada"
fi

# COMENTADO: Código original de remoção de IAM Roles
# ================================================================
# ATENÇÃO: Este código foi comentado para preservar as IAM Roles
# por questões de segurança. Para remover manualmente:
# 1. Acesse o Console AWS IAM
# 2. Vá em "Roles" 
# 3. Procure por roles com "kavoo", "ecsTask", "ecsExecution"
# 4. Delete individualmente após confirmar que não estão em uso
# ================================================================
#
# if [ -n "$iam_roles" ]; then
#     for role_name in $iam_roles; do
#         log "   Processando IAM role: $role_name"
#         
#         # Desanexar políticas gerenciadas
#         attached_policies=$(aws_cmd iam list-attached-role-policies \
#             --role-name $role_name \
#             --query 'AttachedPolicies[].PolicyArn' \
#             --output text 2>/dev/null || echo "")
#         if [ -n "$attached_policies" ]; then
#             for policy_arn in $attached_policies; do
#                 aws_cmd iam detach-role-policy \
#                     --role-name $role_name \
#                     --policy-arn $policy_arn > /dev/null 2>&1 || log "   ⚠️ Erro ao desanexar política $policy_arn"
#             done
#         fi
#         
#         # Deletar políticas inline
#         inline_policies=$(aws_cmd iam list-role-policies \
#             --role-name $role_name \
#             --query 'PolicyNames[]' \
#             --output text 2>/dev/null || echo "")
#         if [ -n "$inline_policies" ]; then
#             for policy_name in $inline_policies; do
#                 aws_cmd iam delete-role-policy \
#                     --role-name $role_name \
#                     --policy-name $policy_name > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar política inline $policy_name"
#             done
#         fi
#         
#         # Deletar role
#         aws_cmd iam delete-role \
#             --role-name $role_name > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar role $role_name"
#     done
# fi

# 20.1. Deletar AWS Budget
log "🗑️ Deletando AWS Budget..."
budgets=$(aws_cmd budgets describe-budgets \
    --account-id $account_id \
    --query 'Budgets[?contains(BudgetName, `kavoo`) || contains(BudgetName, `monthly-budget`)].BudgetName' \
    --output text 2>/dev/null || echo "")
if [ -n "$budgets" ]; then
    for budget_name in $budgets; do
        log "   Deletando budget: $budget_name"
        aws_cmd budgets delete-budget \
            --account-id $account_id \
            --budget-name "$budget_name" > /dev/null 2>&1 || log "   ⚠️ Erro ao deletar budget $budget_name"
    done
else
    log "   ℹ️ Nenhum budget encontrado"
fi
# === FASE 4: LIMPEZA FINAL ===
# 21. Limpar Terraform State (se existir)
if [ -f "terraform.tfstate" ] || [ -f "terraform.tfstate.backup" ]; then
    log "🗑️ Limpando arquivos de estado do Terraform..."
    [ -f "terraform.tfstate" ] && rm -f terraform.tfstate
    [ -f "terraform.tfstate.backup" ] && rm -f terraform.tfstate.backup
    log "   ✅ Arquivos de estado do Terraform removidos"
else
    log "   ℹ️ Nenhum arquivo de estado do Terraform encontrado"
fi
# 22. Verificação final
log "🔍 Executando verificação final..."
echo ""
sleep 5

# Executar verificação se o script existir
if [ -f "./scripts/verify-cleanup.sh" ]; then
    log "📋 Executando script de verificação..."
    ./scripts/verify-cleanup.sh
else
    log "⚠️ Script de verificação não encontrado, realizando verificação básica..."
    
    # Verificações básicas inline
    echo "Verificando recursos restantes:"
    
    # ECS
    remaining_clusters=$(aws_cmd ecs list-clusters --query 'clusterArns[?contains(@, `kavoo`)]' --output text 2>/dev/null || echo "")
    [ -n "$remaining_clusters" ] && echo "   ⚠️ Clusters ECS ainda existem" || echo "   ✅ Nenhum cluster ECS encontrado"
    
    # ECR
    remaining_repos=$(aws_cmd ecr describe-repositories --query 'repositories[?contains(repositoryName, `kavoo`)].repositoryName' --output text 2>/dev/null || echo "")
    [ -n "$remaining_repos" ] && echo "   ⚠️ Repositórios ECR ainda existem" || echo "   ✅ Nenhum repositório ECR encontrado"
    
    # ALB
    remaining_albs=$(aws_cmd elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `kavoo`)].LoadBalancerName' --output text 2>/dev/null || echo "")
    [ -n "$remaining_albs" ] && echo "   ⚠️ Load Balancers ainda existem" || echo "   ✅ Nenhum Load Balancer encontrado"
    
    # RDS
    remaining_rds=$(aws_cmd rds describe-db-instances --query 'DBInstances[?contains(DBInstanceIdentifier, `kavoo`)].DBInstanceIdentifier' --output text 2>/dev/null || echo "")
    [ -n "$remaining_rds" ] && echo "   ⚠️ Instâncias RDS ainda existem" || echo "   ✅ Nenhuma instância RDS encontrada"
fi

echo ""
echo "✅ LIMPEZA CONCLUÍDA!"
echo "===================="
log "🎉 Script de limpeza executado com sucesso"
log "💰 Verifique o console AWS para confirmar que não há mais recursos ativos"
log "📊 Monitore a fatura para confirmar a redução de custos"
echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo "   1. Verifique manualmente o console AWS se necessário"
echo "   2. ⚠️  RECURSOS PRESERVADOS (remoção manual se necessário):"
echo "      - Certificados ACM (Console ACM)"
echo "      - IAM Roles kavoo-* (Console IAM → Roles)"
echo "   3. Monitore a próxima fatura da AWS"
echo ""
echo "🛡️ SEGURANÇA: IAM Roles foram preservadas para evitar problemas de acesso"
echo "   Para remover: Console AWS → IAM → Roles → Delete individual após confirmação"
echo ""