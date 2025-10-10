#!/bin/bash

# Script: check-image-health.sh
# Description: Verifica se as imagens existem no ECR e se os serviços estão saudáveis
# Usage: ./check-image-health.sh [service_name] [--force]
# Author: Copilot Assistant
# Date: 2025-10-02

set -euo pipefail

# Configurações
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurações do projeto
PROJECT_NAME="${PROJECT_NAME:-kavoo}"
ENVIRONMENT="${ENVIRONMENT:-production}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
AWS_PROFILE="${AWS_PROFILE:-}"

# Serviços do projeto
SERVICES=("front" "admins-api" "checkout-api" "members-api" "users-api" "webhooks-api")

# Flags
FORCE_DEPLOY=false
CHECK_SINGLE_SERVICE=""
VERBOSE=false
DRY_RUN=false

# Função para log com timestamp
log() {
    echo -e "${BLUE}[${TIMESTAMP}]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[${TIMESTAMP}] ✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[${TIMESTAMP}] ⚠${NC} $1"
}

log_error() {
    echo -e "${RED}[${TIMESTAMP}] ✗${NC} $1"
}

# Função helper para comandos AWS CLI
aws_cmd() {
    if [[ -n "$AWS_PROFILE" ]]; then
        aws --profile $AWS_PROFILE --region $AWS_REGION "$@"
    else
        aws --region $AWS_REGION "$@"
    fi
}

# Função para mostrar ajuda
show_help() {
    cat << EOF
Uso: $0 [OPTIONS] [SERVICE_NAME]

Este script verifica se as imagens Docker existem no ECR e se os serviços estão saudáveis.

OPÇÕES:
    -h, --help          Mostra esta ajuda
    -f, --force         Força o deploy mesmo se a imagem existir e estiver saudável
    -v, --verbose       Modo verboso
    -d, --dry-run       Apenas simula as verificações sem executar ações
    --check-ecr         Apenas verifica se as imagens existem no ECR
    --check-health      Apenas verifica a saúde dos serviços
    --list-services     Lista todos os serviços disponíveis

ARGUMENTOS:
    SERVICE_NAME        Nome do serviço específico para verificar (opcional)
                       Se não especificado, verifica todos os serviços

EXEMPLOS:
    $0                          # Verifica todos os serviços
    $0 front                    # Verifica apenas o serviço front
    $0 --force checkout-api     # Força deploy do checkout-api
    $0 --check-ecr              # Apenas verifica ECR
    $0 --check-health           # Apenas verifica saúde dos serviços

SERVIÇOS DISPONÍVEIS:
    $(printf "    %s\n" "${SERVICES[@]}")

VARIÁVEIS DE AMBIENTE:
    AWS_REGION          Região AWS (padrão: us-east-1)
    AWS_ACCOUNT_ID      ID da conta AWS
    PROJECT_NAME        Nome do projeto (padrão: kavoo)
    ENVIRONMENT         Ambiente (padrão: production)
EOF
}

# Parse dos argumentos
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--force)
                FORCE_DEPLOY=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --check-ecr)
                CHECK_ECR_ONLY=true
                shift
                ;;
            --check-health)
                CHECK_HEALTH_ONLY=true
                shift
                ;;
            --list-services)
                printf "%s\n" "${SERVICES[@]}"
                exit 0
                ;;
            -*)
                log_error "Opção desconhecida: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$CHECK_SINGLE_SERVICE" ]]; then
                    CHECK_SINGLE_SERVICE="$1"
                else
                    log_error "Múltiplos serviços especificados: $CHECK_SINGLE_SERVICE e $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

# Função para verificar dependências
check_dependencies() {
    local deps=("aws" "jq" "curl")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Dependências faltando: ${missing[*]}"
        log_error "Instale as dependências e tente novamente"
        exit 1
    fi
}

# Função para verificar configurações AWS
check_aws_config() {
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        log "Obtendo AWS Account ID..."
        AWS_ACCOUNT_ID=$(aws_cmd sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    fi

    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        log_error "Não foi possível obter AWS Account ID. Verifique suas credenciais AWS."
        exit 1
    fi

    if [[ "$VERBOSE" == true ]]; then
        log "AWS Account ID: $AWS_ACCOUNT_ID"
        log "AWS Region: $AWS_REGION"
    fi
}

# Função para verificar se imagem existe no ECR
check_image_exists() {
    local service_name="$1"
    local tag="${2:-latest}"
    local repository_name="${PROJECT_NAME}/${service_name}"
    
    if [[ "$VERBOSE" == true ]]; then
        log "Verificando imagem: ${repository_name}:${tag}"
    fi

    # Verifica se o repositório existe
    if ! aws_cmd ecr describe-repositories --repository-names "$repository_name" &> /dev/null; then
        if [[ "$VERBOSE" == true ]]; then
            log_warning "Repositório ECR não existe: $repository_name"
        fi
        return 1
    fi

    # Verifica se a imagem existe
    if aws_cmd ecr describe-images --repository-name "$repository_name" --image-ids imageTag="$tag" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Função para obter informações da imagem
get_image_info() {
    local service_name="$1"
    local tag="${2:-latest}"
    local repository_name="${PROJECT_NAME}/${service_name}"
    
    local image_info=$(aws_cmd ecr describe-images \
        --repository-name "$repository_name" \
        --image-ids imageTag="$tag" \
        --query 'imageDetails[0]' \
        --output json 2>/dev/null || echo "{}")
    
    echo "$image_info"
}

# Função para verificar saúde do serviço via ECS
check_ecs_service_health() {
    local service_name="$1"
    local cluster_name="${PROJECT_NAME}-cluster"
    local ecs_service_name="${PROJECT_NAME}-${service_name}"
    
    if [[ "$VERBOSE" == true ]]; then
        log "Verificando saúde do serviço ECS: $ecs_service_name"
    fi

    # Verifica se o cluster existe
    if ! aws_cmd ecs describe-clusters --clusters "$cluster_name" --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
        if [[ "$VERBOSE" == true ]]; then
            log_warning "Cluster ECS não está ativo: $cluster_name"
        fi
        return 1
    fi

    # Verifica o status do serviço
    local service_info=$(aws_cmd ecs describe-services \
        --cluster "$cluster_name" \
        --services "$ecs_service_name" \
        --query 'services[0]' \
        --output json 2>/dev/null || echo "{}")
    
    if [[ "$service_info" == "{}" ]] || [[ "$service_info" == "null" ]]; then
        if [[ "$VERBOSE" == true ]]; then
            log_warning "Serviço ECS não encontrado: $ecs_service_name"
        fi
        return 1
    fi

    local running_count=$(echo "$service_info" | jq -r '.runningCount // 0')
    local desired_count=$(echo "$service_info" | jq -r '.desiredCount // 0')
    local status=$(echo "$service_info" | jq -r '.status // "UNKNOWN"')

    if [[ "$status" == "ACTIVE" ]] && [[ "$running_count" -eq "$desired_count" ]] && [[ "$desired_count" -gt 0 ]]; then
        return 0
    else
        if [[ "$VERBOSE" == true ]]; then
            log_warning "Serviço não saudável - Status: $status, Running: $running_count, Desired: $desired_count"
        fi
        return 1
    fi
}

# Função para verificar saúde via endpoint HTTP
check_http_health() {
    local service_name="$1"
    local health_endpoint=""
    
    # Determina o endpoint baseado no serviço
    case "$service_name" in
        "front")
            health_endpoint="http://localhost:3000/health"
            ;;
        *"-api")
            # Para APIs, usa o ALB se disponível
            health_endpoint="https://${service_name}.${PROJECT_NAME}.com/health"
            ;;
        *)
            log_warning "Endpoint de saúde não configurado para: $service_name"
            return 1
            ;;
    esac
    
    if [[ "$VERBOSE" == true ]]; then
        log "Verificando endpoint: $health_endpoint"
    fi

    # Tenta fazer requisição HTTP
    if curl -sf --max-time 10 "$health_endpoint" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Função principal para verificar um serviço
check_service() {
    local service_name="$1"
    local needs_deploy=false
    local reasons=()

    log "=== Verificando serviço: $service_name ==="

    # Verifica se a imagem existe no ECR
    if check_image_exists "$service_name"; then
        log_success "Imagem existe no ECR: ${PROJECT_NAME}/${service_name}:latest"
        
        if [[ "$VERBOSE" == true ]]; then
            local image_info=$(get_image_info "$service_name")
            local push_date=$(echo "$image_info" | jq -r '.imagePushedAt // "Unknown"')
            local size_mb=$(echo "$image_info" | jq -r '.imageSizeInBytes // 0 | . / 1024 / 1024 | floor')
            log "  Data do push: $push_date"
            log "  Tamanho: ${size_mb}MB"
        fi
    else
        log_warning "Imagem não existe no ECR: ${PROJECT_NAME}/${service_name}:latest"
        needs_deploy=true
        reasons+=("imagem não existe no ECR")
    fi

    # Verifica saúde do serviço ECS
    if check_ecs_service_health "$service_name"; then
        log_success "Serviço ECS está saudável"
    else
        log_warning "Serviço ECS não está saudável"
        needs_deploy=true
        reasons+=("serviço ECS não saudável")
    fi

    # Verifica saúde via HTTP (opcional)
    if check_http_health "$service_name"; then
        log_success "Endpoint HTTP está respondendo"
    else
        log_warning "Endpoint HTTP não está respondendo (pode ser normal se ALB não estiver configurado)"
    fi

    # Determina se precisa fazer deploy
    if [[ "$FORCE_DEPLOY" == true ]]; then
        needs_deploy=true
        reasons+=("deploy forçado")
    fi

    # Resultado final
    if [[ "$needs_deploy" == true ]]; then
        log_error "Deploy necessário para $service_name"
        if [[ ${#reasons[@]} -gt 0 ]]; then
            log "Motivos: ${reasons[*]}"
        fi
        return 1
    else
        log_success "Serviço $service_name está OK - Deploy não necessário"
        return 0
    fi
}

# Função para listar serviços que precisam de deploy
get_services_needing_deploy() {
    local services_to_check=("${@}")
    local services_needing_deploy=()

    for service in "${services_to_check[@]}"; do
        if ! check_service "$service" > /dev/null 2>&1; then
            services_needing_deploy+=("$service")
        fi
    done

    printf "%s\n" "${services_needing_deploy[@]}"
}

# Função principal
main() {
    parse_args "$@"
    
    log "Iniciando verificação de imagens e saúde dos serviços..."
    log "Projeto: $PROJECT_NAME | Ambiente: $ENVIRONMENT"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warning "Modo DRY RUN - Nenhuma ação será executada"
    fi

    check_dependencies
    check_aws_config

    # Determina quais serviços verificar
    local services_to_check=()
    if [[ -n "$CHECK_SINGLE_SERVICE" ]]; then
        # Valida se o serviço existe na lista
        if [[ ! " ${SERVICES[*]} " =~ " $CHECK_SINGLE_SERVICE " ]]; then
            log_error "Serviço não encontrado: $CHECK_SINGLE_SERVICE"
            log "Serviços disponíveis: ${SERVICES[*]}"
            exit 1
        fi
        services_to_check=("$CHECK_SINGLE_SERVICE")
    else
        services_to_check=("${SERVICES[@]}")
    fi

    # Executa verificações
    local failed_services=()
    local success_count=0

    for service in "${services_to_check[@]}"; do
        if check_service "$service"; then
            ((success_count++))
        else
            failed_services+=("$service")
        fi
        echo
    done

    # Resumo final
    log "=== RESUMO ==="
    log_success "Serviços OK: $success_count/${#services_to_check[@]}"
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        log_error "Serviços que precisam de deploy: ${failed_services[*]}"
        
        # Cria arquivo com lista de serviços para deploy
        local deploy_list_file="${PROJECT_ROOT}/.deploy-needed"
        printf "%s\n" "${failed_services[@]}" > "$deploy_list_file"
        log "Lista salva em: $deploy_list_file"
        
        exit 1
    else
        log_success "Todos os serviços estão OK!"
        
        # Remove arquivo de deploy se existir
        local deploy_list_file="${PROJECT_ROOT}/.deploy-needed"
        [[ -f "$deploy_list_file" ]] && rm -f "$deploy_list_file"
        
        exit 0
    fi
}

# Executa apenas se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi