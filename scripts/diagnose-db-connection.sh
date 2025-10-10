#!/bin/bash
# diagnose-db-connection.sh - Diagnóstico de conexão do banco de dados

echo "🔍 DIAGNÓSTICO DE CONEXÃO DO BANCO"
echo "=================================="

AWS_REGION="us-east-1"
AWS_PROFILE="${AWS_PROFILE:-}"

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
echo ""

echo "1. 📊 Status do RDS:"
echo "=================="
rds_status=$(aws_cmd rds describe-db-instances --db-instance-identifier kavoo-db \
    --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,Port:Endpoint.Port,VPC:DBSubnetGroup.VpcId,AZ:AvailabilityZone}' \
    --output table 2>/dev/null || echo "❌ RDS kavoo-db não encontrado")

if [ "$rds_status" != "❌ RDS kavoo-db não encontrado" ]; then
    echo "$rds_status"
    
    # Verificar se está available
    db_status=$(aws_cmd rds describe-db-instances --db-instance-identifier kavoo-db \
        --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null)
    echo ""
    echo "🔍 Status detalhado: $db_status"
    
    if [ "$db_status" != "available" ]; then
        echo "⚠️  PROBLEMA: RDS não está disponível!"
        echo "   Status atual: $db_status"
        echo ""
        echo "🔧 SOLUÇÃO: Iniciar o RDS"
        echo "   Comando: aws rds start-db-instance --db-instance-identifier kavoo-db"
        echo ""
    else
        echo "✅ RDS está disponível"
    fi
else
    echo "$rds_status"
    echo ""
    echo "🔍 Tentando buscar por outras instâncias RDS relacionadas ao kavoo:"
    aws_cmd rds describe-db-instances \
        --query 'DBInstances[?contains(DBInstanceIdentifier, `kavoo`)].{Identifier:DBInstanceIdentifier,Status:DBInstanceStatus,Endpoint:Endpoint.Address}' \
        --output table 2>/dev/null || echo "   ❌ Nenhuma instância RDS encontrada"
fi

echo ""
echo "2. 🔐 Secrets Manager:"
echo "====================="
secrets=$(aws_cmd secretsmanager list-secrets \
    --query 'SecretList[?contains(Name, `kavoo`)].{Name:Name,LastChanged:LastChangedDate}' \
    --output table 2>/dev/null || echo "❌ Erro ao listar secrets")

if [ "$secrets" != "❌ Erro ao listar secrets" ]; then
    echo "$secrets"
    echo ""
    
    # Verificar conteúdo dos secrets específicos de cada API
    echo "🔍 Verificando secrets específicos das APIs:"
    for api in admins checkout members users webhooks; do
        echo "   Verificando kavoo-${api}-api-db-credentials:"
        db_secret=$(aws_cmd secretsmanager get-secret-value \
            --secret-id "kavoo-${api}-api-db-credentials" \
            --query 'SecretString' \
            --output text 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$db_secret" ]; then
            echo "     ✅ Secret encontrado"
            # Verificar se contém as chaves necessárias sem expor os valores
            echo "     Chaves disponíveis:"
            echo "$db_secret" | jq -r 'keys[]' 2>/dev/null | sed 's/^/        /' || echo "        ❌ Erro ao parsear JSON do secret"
        
        # Verificar se tem host/endpoint
        has_host=$(echo "$db_secret" | jq -r '.host // .endpoint // "NOT_FOUND"' 2>/dev/null)
            has_host=$(echo "$db_secret" | jq -r '.database_url // "NOT_FOUND"' 2>/dev/null)
            if [ "$has_host" != "NOT_FOUND" ] && [ "$has_host" != "null" ]; then
                echo "     ✅ Endpoint configurado: ${has_host:0:30}..."
            else
                echo "     ❌ Endpoint não encontrado no secret"
            fi
        else
            echo "     ❌ Erro ao acessar secret kavoo-${api}-api-db-credentials"
        fi
    done
else
    echo "$secrets"
fi

echo ""
echo "3. 🛡️ Security Groups do Database:"
echo "================================="
db_sgs=$(aws_cmd ec2 describe-security-groups \
    --filters "Name=group-name,Values=*kavoo*database*,*kavoo*db*" \
    --query 'SecurityGroups[].{GroupName:GroupName,GroupId:GroupId}' \
    --output table 2>/dev/null)

if [ -n "$db_sgs" ] && [ "$db_sgs" != "[]" ]; then
    echo "$db_sgs"
    echo ""
    
    # Verificar regras de entrada para PostgreSQL (porta 5432)
    echo "🔍 Regras de entrada para porta 5432 (PostgreSQL):"
    aws_cmd ec2 describe-security-groups \
        --filters "Name=group-name,Values=*kavoo*database*,*kavoo*db*" \
        --query 'SecurityGroups[].IpPermissions[?FromPort==`5432`].{Protocol:IpProtocol,Port:FromPort,Sources:IpRanges[].CidrIp,SourceSGs:UserIdGroupPairs[].GroupId}' \
        --output table 2>/dev/null || echo "   ❌ Nenhuma regra para porta 5432 encontrada"
else
    echo "❌ Nenhum security group do database encontrado"
fi

echo ""
echo "4. 🌐 Security Groups do ECS:"
echo "============================"
ecs_sgs=$(aws_cmd ec2 describe-security-groups \
    --filters "Name=group-name,Values=*kavoo*ecs*" \
    --query 'SecurityGroups[].{GroupName:GroupName,GroupId:GroupId}' \
    --output table 2>/dev/null)

if [ -n "$ecs_sgs" ] && [ "$ecs_sgs" != "[]" ]; then
    echo "$ecs_sgs"
else
    echo "❌ Nenhum security group do ECS encontrado"
fi

echo ""
echo "5. 📋 Task Definition Atual (kavoo-checkout-api):"
echo "==============================================="
# Buscar a task definition mais recente
latest_td=$(aws_cmd ecs describe-task-definition \
    --task-definition kavoo-checkout-api \
    --query 'taskDefinition.revision' \
    --output text 2>/dev/null)

if [ -n "$latest_td" ] && [ "$latest_td" != "None" ]; then
    echo "📊 Revisão atual: $latest_td"
    echo ""
    echo "🔍 Variáveis de ambiente:"
    aws_cmd ecs describe-task-definition \
        --task-definition kavoo-checkout-api:$latest_td \
        --query 'taskDefinition.containerDefinitions[0].environment' \
        --output table 2>/dev/null || echo "   ❌ Erro ao obter variáveis de ambiente"
    
    echo ""
    echo "🔍 Secrets referenciados:"
    aws_cmd ecs describe-task-definition \
        --task-definition kavoo-checkout-api:$latest_td \
        --query 'taskDefinition.containerDefinitions[0].secrets' \
        --output table 2>/dev/null || echo "   ❌ Nenhum secret referenciado"
else
    echo "❌ Task definition kavoo-checkout-api não encontrada"
fi

echo ""
echo "6. 📊 Últimos Logs do Container:"
echo "==============================="
echo "🔍 Últimos logs (últimos 10 minutos):"
start_time=$(date -d '10 minutes ago' +%s)000

recent_logs=$(aws_cmd logs filter-log-events \
    --log-group-name "/ecs/kavoo-checkout-api" \
    --start-time $start_time \
    --query 'events[-10:].message' \
    --output text 2>/dev/null)

if [ -n "$recent_logs" ]; then
    echo "$recent_logs" | tail -10
else
    echo "❌ Nenhum log recente encontrado ou log group não existe"
    
    # Verificar se o log group existe
    echo ""
    echo "🔍 Verificando log groups disponíveis:"
    aws_cmd logs describe-log-groups \
        --log-group-name-prefix "/ecs/kavoo" \
        --query 'logGroups[].logGroupName' \
        --output table 2>/dev/null || echo "   ❌ Nenhum log group encontrado"
fi

echo ""
echo "7. 🎯 Status Atual do Serviço ECS:"
echo "================================="
service_status=$(aws_cmd ecs describe-services \
    --cluster kavoo-cluster \
    --services kavoo-checkout-api \
    --query 'services[0].{DesiredCount:desiredCount,RunningCount:runningCount,PendingCount:pendingCount,Status:status}' \
    --output table 2>/dev/null)

if [ -n "$service_status" ]; then
    echo "$service_status"
else
    echo "❌ Serviço kavoo-checkout-api não encontrado no cluster kavoo-cluster"
fi

echo ""
echo "8. 🔍 Análise de Tasks Falhadas:"
echo "==============================="
# Buscar tasks recentes que falharam
failed_tasks=$(aws_cmd ecs list-tasks \
    --cluster kavoo-cluster \
    --service-name kavoo-checkout-api \
    --desired-status STOPPED \
    --query 'taskArns[0:3]' \
    --output text 2>/dev/null)

if [ -n "$failed_tasks" ] && [ "$failed_tasks" != "None" ]; then
    for task_arn in $failed_tasks; do
        echo "📊 Analisando task: $task_arn"
        aws_cmd ecs describe-tasks \
            --cluster kavoo-cluster \
            --tasks $task_arn \
            --query 'tasks[0].{StoppedReason:stoppedReason,StoppedAt:stoppedAt,LastStatus:lastStatus}' \
            --output table 2>/dev/null || echo "   ❌ Erro ao obter detalhes da task"
        echo ""
    done
else
    echo "ℹ️ Nenhuma task falhada recente encontrada"
fi

echo ""
echo "=================================="
echo "🎯 RESUMO DO DIAGNÓSTICO:"
echo "=================================="

# Verificações principais
db_available=$(aws_cmd rds describe-db-instances --db-instance-identifier kavoo-db --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null)
secrets_exist=$(aws_cmd secretsmanager list-secrets --query 'SecretList[?contains(Name, `kavoo-`) && contains(Name, `-api-db-credentials`)].Name' --output text 2>/dev/null)

echo "📊 Status dos Componentes:"
if [ "$db_available" = "available" ]; then
    echo "   ✅ RDS Database: Disponível"
elif [ -n "$db_available" ]; then
    echo "   ⚠️ RDS Database: $db_available (não disponível)"
else
    echo "   ❌ RDS Database: Não encontrado"
fi

if [ -n "$secrets_exist" ]; then
    echo "   ✅ Secrets Manager: Configurado"
else
    echo "   ❌ Secrets Manager: Secret não encontrado"
fi

echo ""
echo "🔧 PRÓXIMOS PASSOS SUGERIDOS:"
if [ "$db_available" != "available" ]; then
    echo "   1. 🚀 Iniciar o RDS: aws rds start-db-instance --db-instance-identifier kavoo-db"
fi

if [ -z "$secrets_exist" ]; then
    echo "   2. 🔐 Verificar/recriar secrets do banco"
fi

echo "   3. 🛡️ Verificar conectividade entre Security Groups"
echo "   4. 🔍 Analisar logs detalhados da aplicação"

echo ""
echo "📅 Diagnóstico concluído em: $(date)"