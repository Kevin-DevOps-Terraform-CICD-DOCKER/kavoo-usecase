#!/bin/bash
# pre-cleanup-check.sh - Verifica o que será removido ANTES da limpeza

echo "🔍 PRÉ-VERIFICAÇÃO DE LIMPEZA KAVOO"
echo "===================================="
echo "📋 Este script mostra EXATAMENTE o que será removido"
echo ""

AWS_REGION="us-east-1"
found_resources=false

# Função para contar e listar recursos
check_and_list() {
    local resource_type="$1"
    local aws_command="$2"
    local count_command="$3"
    
    echo "🔎 $resource_type:"
    
    if result=$(eval "$aws_command" 2>/dev/null) && [ -n "$result" ] && [ "$result" != "[]" ] && [ "$result" != "None" ]; then
        found_resources=true
        echo "   ✅ Encontrados recursos que serão REMOVIDOS:"
        echo "$result" | sed 's/^/      /'
        
        if [ -n "$count_command" ]; then
            count=$(eval "$count_command" 2>/dev/null || echo "0")
            echo "   📊 Total: $count recursos"
        fi
    else
        echo "   ❌ Nenhum recurso encontrado"
    fi
    echo ""
}

echo "🚨 RECURSOS QUE SERÃO DELETADOS:"
echo "================================="

# ECS
check_and_list "ECS Clusters" \
    "aws ecs list-clusters --region $AWS_REGION --query 'clusterArns[?contains(@, \`kavoo\`)]' --output table" \
    "aws ecs list-clusters --region $AWS_REGION --query 'length(clusterArns[?contains(@, \`kavoo\`)])'"

check_and_list "ECS Services" \
    "aws ecs list-services --cluster kavoo-cluster --region $AWS_REGION --query 'serviceArns[]' --output table 2>/dev/null || echo 'Cluster não encontrado'" \
    "aws ecs list-services --cluster kavoo-cluster --region $AWS_REGION --query 'length(serviceArns)' 2>/dev/null || echo '0'"

# ECR
check_and_list "ECR Repositories" \
    "aws ecr describe-repositories --region $AWS_REGION --query 'repositories[?contains(repositoryName, \`kavoo\`)].repositoryName' --output table" \
    "aws ecr describe-repositories --region $AWS_REGION --query 'length(repositories[?contains(repositoryName, \`kavoo\`)])'"

# Load Balancers
check_and_list "Application Load Balancers" \
    "aws elbv2 describe-load-balancers --region $AWS_REGION --query 'LoadBalancers[?contains(LoadBalancerName, \`kavoo\`)].LoadBalancerName' --output table" \
    "aws elbv2 describe-load-balancers --region $AWS_REGION --query 'length(LoadBalancers[?contains(LoadBalancerName, \`kavoo\`)])'"

# Target Groups
check_and_list "Target Groups" \
    "aws elbv2 describe-target-groups --region $AWS_REGION --query 'TargetGroups[?contains(TargetGroupName, \`kavoo\`)].TargetGroupName' --output table" \
    "aws elbv2 describe-target-groups --region $AWS_REGION --query 'length(TargetGroups[?contains(TargetGroupName, \`kavoo\`)])'"

# Security Groups
check_and_list "Security Groups" \
    "aws ec2 describe-security-groups --region $AWS_REGION --filters 'Name=group-name,Values=*kavoo*' --query 'SecurityGroups[?GroupName!=\`default\`].GroupName' --output table" \
    "aws ec2 describe-security-groups --region $AWS_REGION --filters 'Name=group-name,Values=*kavoo*' --query 'length(SecurityGroups[?GroupName!=\`default\`])'"

# Task Definitions
check_and_list "Task Definitions" \
    "aws ecs list-task-definitions --region $AWS_REGION --query 'taskDefinitionArns[?contains(@, \`kavoo\`)]' --output table" \
    "aws ecs list-task-definitions --region $AWS_REGION --query 'length(taskDefinitionArns[?contains(@, \`kavoo\`)])'"

# Route 53
check_and_list "Route 53 Hosted Zones" \
    "aws route53 list-hosted-zones --query 'HostedZones[?contains(Name, \`kavoo\`)].Name' --output table" \
    "aws route53 list-hosted-zones --query 'length(HostedZones[?contains(Name, \`kavoo\`)])'"

# ACM Certificates
check_and_list "SSL Certificates" \
    "aws acm list-certificates --region $AWS_REGION --query 'CertificateSummaryList[?contains(DomainName, \`kavoo\`)].DomainName' --output table" \
    "aws acm list-certificates --region $AWS_REGION --query 'length(CertificateSummaryList[?contains(DomainName, \`kavoo\`)])'"

# VPC
check_and_list "VPCs Personalizadas" \
    "aws ec2 describe-vpcs --region $AWS_REGION --filters 'Name=tag:Name,Values=*kavoo*' --query 'Vpcs[?IsDefault==\`false\`].VpcId' --output table" \
    "aws ec2 describe-vpcs --region $AWS_REGION --filters 'Name=tag:Name,Values=*kavoo*' --query 'length(Vpcs[?IsDefault==\`false\`])'"

# Subnets
check_and_list "Subnets Personalizadas" \
    "aws ec2 describe-subnets --region $AWS_REGION --filters 'Name=tag:Name,Values=*kavoo*' --query 'Subnets[].SubnetId' --output table" \
    "aws ec2 describe-subnets --region $AWS_REGION --filters 'Name=tag:Name,Values=*kavoo*' --query 'length(Subnets[])'"

# RDS
check_and_list "RDS Instances" \
    "aws rds describe-db-instances --region $AWS_REGION --query 'DBInstances[?contains(DBInstanceIdentifier, \`kavoo\`)].DBInstanceIdentifier' --output table" \
    "aws rds describe-db-instances --region $AWS_REGION --query 'length(DBInstances[?contains(DBInstanceIdentifier, \`kavoo\`)])'"

# ElastiCache
check_and_list "ElastiCache Clusters" \
    "aws elasticache describe-cache-clusters --region $AWS_REGION --query 'CacheClusters[?contains(CacheClusterId, \`kavoo\`)].CacheClusterId' --output table" \
    "aws elasticache describe-cache-clusters --region $AWS_REGION --query 'length(CacheClusters[?contains(CacheClusterId, \`kavoo\`)])'"

# Secrets Manager
check_and_list "Secrets Manager" \
    "aws secretsmanager list-secrets --region $AWS_REGION --query 'SecretList[?contains(Name, \`kavoo\`)].Name' --output table" \
    "aws secretsmanager list-secrets --region $AWS_REGION --query 'length(SecretList[?contains(Name, \`kavoo\`)])'"

# IAM Roles
check_and_list "IAM Roles" \
    "aws iam list-roles --query 'Roles[?contains(RoleName, \`kavoo\`) || contains(RoleName, \`ecsTask\`) || contains(RoleName, \`ecsExecution\`)].RoleName' --output table" \
    "aws iam list-roles --query 'length(Roles[?contains(RoleName, \`kavoo\`) || contains(RoleName, \`ecsTask\`) || contains(RoleName, \`ecsExecution\`)])'"

# CloudWatch Log Groups
check_and_list "CloudWatch Log Groups" \
    "aws logs describe-log-groups --region $AWS_REGION --log-group-name-prefix '/ecs/kavoo' --query 'logGroups[].logGroupName' --output table" \
    "aws logs describe-log-groups --region $AWS_REGION --log-group-name-prefix '/ecs/kavoo' --query 'length(logGroups[])'"

echo "================================="
if [ "$found_resources" = true ]; then
    echo "⚠️  ATENÇÃO: RECURSOS ENCONTRADOS!"
    echo ""
    echo "🔥 Os recursos listados acima serão PERMANENTEMENTE DELETADOS"
    echo "💀 Esta ação é IRREVERSÍVEL"
    echo "💰 Após a exclusão, não haverá mais custos relacionados"
    echo ""
    echo "🚀 Para prosseguir com a limpeza, execute:"
    echo "   ./scripts/cleanup-kavoo-infrastructure.sh"
    echo ""
    echo "🛡️  Para cancelar, pressione Ctrl+C"
else
    echo "✅ NENHUM RECURSO KAVOO ENCONTRADO"
    echo ""
    echo "🎉 Sua conta AWS está limpa!"
    echo "💰 Não há recursos Kavoo gerando custos"
fi

echo ""
echo "📊 Verificação completa em: $(date)"