#!/bin/bash

set -euo pipefail

# Configurações
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Versão do script
SCRIPT_VERSION="2.1.0-network-fix"

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
ANALYZE_ONLY=false
OUTPUT_FORMAT="json"
OUTPUT_FILE="deploy-matrix.json"
FORCE_DEPLOY=false
BUILD_ONLY=false
PUSH_ONLY=false
SKIP_HEALTH_CHECK=false
TARGET_SERVICE=""
PARALLEL_BUILD=false
VERBOSE=false
DRY_RUN=false

# Estatísticas
BUILD_COUNT=0
PUSH_COUNT=0
SKIP_COUNT=0
ERROR_COUNT=0

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

# Função para análise de serviços (novo modo)
analyze_services() {
    log "=== MODO ANÁLISE - Verificando status dos serviços ==="
    
    # Desabilita exit on error temporariamente para análise
    set +e
    
    local services_json="[]"
    local needs_deploy=0
    local already_healthy=0
    
    for service in "${SERVICES[@]}"; do
        log "Analisando serviço: $service"
        
        # Análise mais robusta com tratamento de erro
        local service_analysis
        if service_analysis=$(analyze_single_service "$service" 2>/dev/null); then
            # Valida se o JSON retornado é válido
            if echo "$service_analysis" | jq . >/dev/null 2>&1; then
                local needs_build=$(echo "$service_analysis" | jq -r '.needs_deploy // false')
                
                # Adiciona serviço ao array JSON de forma segura
                services_json=$(echo "$services_json" | jq --argjson service "$service_analysis" '. += [$service]')
                
                if [[ "$needs_build" == "true" ]]; then
                    ((needs_deploy++))
                    log_warning "⚡ $service precisa de deploy"
                else
                    ((already_healthy++))
                    log_success "✅ $service está saudável, deploy não necessário"
                fi
            else
                log_error "JSON inválido retornado para serviço $service"
                # Cria um JSON de fallback para o serviço com erro
                local fallback_json=$(jq -n \
                    --arg name "$service" \
                    --arg error "json_parse_error" \
                    '{
                        name: $name,
                        error: $error,
                        needs_deploy: true,
                        reason: "analysis_failed"
                    }')
                services_json=$(echo "$services_json" | jq --argjson service "$fallback_json" '. += [$service]')
                ((needs_deploy++))
            fi
        else
            log_error "Falha na análise do serviço $service"
            # Cria JSON de fallback para erro de análise
            local fallback_json=$(jq -n \
                --arg name "$service" \
                --arg error "analysis_failed" \
                '{
                    name: $name,
                    error: $error,
                    needs_deploy: true,
                    reason: "service_analysis_failed"
                }')
            services_json=$(echo "$services_json" | jq --argjson service "$fallback_json" '. += [$service]')
            ((needs_deploy++))
        fi
    done
    
    # Reabilita exit on error
    set -e
    
    # Monta resultado final com validação
    local analysis_result
    analysis_result=$(jq -n \
        --argjson services "$services_json" \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --argjson total "${#SERVICES[@]}" \
        --argjson needs_deploy "$needs_deploy" \
        --argjson already_healthy "$already_healthy" \
        '{
            services: $services,
            summary: {
                timestamp: $timestamp,
                total_services: $total,
                needs_deploy: $needs_deploy,
                already_healthy: $already_healthy,
                force_deploy: false
            }
        }')
    
    # Valida o JSON final antes de salvar
    if echo "$analysis_result" | jq . >/dev/null 2>&1; then
        echo "$analysis_result" > "$OUTPUT_FILE"
        log_success "Análise salva em: $OUTPUT_FILE"
    else
        log_error "Erro ao gerar JSON final - salvando resultado básico"
        # Fallback para JSON mínimo válido
        jq -n \
            --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
            --argjson total "${#SERVICES[@]}" \
            --argjson error_count "$((${#SERVICES[@]} - already_healthy))" \
            '{
                services: [],
                summary: {
                    timestamp: $timestamp,
                    total_services: $total,
                    needs_deploy: $error_count,
                    already_healthy: 0,
                    force_deploy: false,
                    error: "json_generation_failed"
                }
            }' > "$OUTPUT_FILE"
    fi
    
    # Mostra resumo
    log "=== RESUMO DA ANÁLISE ==="
    log "Total de serviços: ${#SERVICES[@]}"
    log_warning "Precisam de deploy: $needs_deploy"
    log_success "Já saudáveis: $already_healthy"
    
    if [[ "$needs_deploy" -gt 0 ]]; then
        log "Serviços que precisam de deploy:"
        echo "$analysis_result" | jq -r '.services[] | select(.needs_deploy == true) | "  - " + .name + " (" + .reason + ")"'
    fi
    
    return 0
}

# Função para análise de um único serviço
analyze_single_service() {
    local service_name="$1"
    
    # Valida que o serviço é válido
    local config
    if ! config=($(get_service_config "$service_name" 2>/dev/null)); then
        jq -n \
            --arg name "$service_name" \
            --arg error "service_config_not_found" \
            '{
                name: $name,
                error: $error,
                needs_deploy: false,
                reason: "invalid_service"
            }'
        return 0
    fi
    
    local context_path="${PROJECT_ROOT}/${config[0]}"
    local dockerfile="${config[1]}"
    local port="${config[2]}"
    
    local image_exists=false
    local service_healthy=false
    local needs_deploy=true
    local reason="unknown"
    
    # Verifica se imagem existe no ECR (com tratamento de erro)
    local repo_name="${PROJECT_NAME}/${service_name}"
    if [[ -n "$AWS_ACCOUNT_ID" ]]; then
        # Usa um método mais seguro para verificar imagem
        local describe_result
        if describe_result=$(aws_cmd ecr describe-images \
            --repository-name "$repo_name" \
            --image-ids imageTag=latest \
            --output json 2>/dev/null); then
            
            # Verifica se o resultado contém imagens
            local image_count=$(echo "$describe_result" | jq '.imageDetails | length' 2>/dev/null || echo "0")
            if [[ "$image_count" -gt 0 ]]; then
                image_exists=true
            fi
        fi
    fi
    
    # Verifica saúde do serviço ECS se imagem existe
    if [[ "$image_exists" == true ]]; then
        if [[ -f "${SCRIPT_DIR}/check-image-health.sh" ]]; then
            # Executa verificação de saúde com timeout
            if timeout 30 "${SCRIPT_DIR}/check-image-health.sh" "$service_name" --quiet >/dev/null 2>&1; then
                service_healthy=true
                needs_deploy=false
                reason="image_exists_and_healthy"
            else
                reason="image_exists_but_unhealthy"
            fi
        else
            reason="image_exists_health_check_unavailable"
        fi
    else
        reason="image_not_found"
    fi
    
    # Se forçado, sempre precisa de deploy
    if [[ "$FORCE_DEPLOY" == true ]]; then
        needs_deploy=true
        reason="force_deploy_requested"
    fi
    
    # Monta URI da imagem de forma segura
    local image_uri
    if [[ -n "$AWS_ACCOUNT_ID" ]]; then
        image_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}/${service_name}:latest"
    else
        image_uri="ACCOUNT_ID_NOT_SET.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}/${service_name}:latest"
    fi
    
    # Sanitiza paths para JSON (escapa caracteres especiais)
    local safe_context_path=$(printf '%s' "$context_path" | sed 's/\\/\\\\/g; s/"/\\"/g')
    local safe_dockerfile=$(printf '%s' "$dockerfile" | sed 's/\\/\\\\/g; s/"/\\"/g')
    
    # Retorna JSON do serviço com validação
    jq -n \
        --arg name "$service_name" \
        --arg context_path "$safe_context_path" \
        --arg dockerfile "$safe_dockerfile" \
        --argjson port "$port" \
        --argjson image_exists "$image_exists" \
        --argjson service_healthy "$service_healthy" \
        --argjson needs_deploy "$needs_deploy" \
        --arg reason "$reason" \
        --arg image_uri "$image_uri" \
        '{
            name: $name,
            context_path: $context_path,
            dockerfile: $dockerfile,
            port: $port,
            image_exists: $image_exists,
            service_healthy: $service_healthy,
            needs_deploy: $needs_deploy,
            reason: $reason,
            image_uri: $image_uri
        }'
}

# Função para mostrar ajuda
show_help() {
    cat << EOF
Uso: $0 [OPTIONS] [SERVICE_NAME]

Este script pode funcionar em dois modos:
1. MODO ANÁLISE: Gera matriz JSON para GitHub Actions (padrão)
2. MODO DEPLOY: Deploy inteligente tradicional

OPÇÕES PRINCIPAIS:
    -h, --help              Mostra esta ajuda
    -a, --analyze-only      Modo análise - gera apenas matriz JSON (PADRÃO)
    --output-file FILE      Arquivo de saída da análise (padrão: deploy-matrix.json)
    --output-format FORMAT  Formato de saída (json) (padrão: json)
    --fix-network           Corrige rede de todos os serviços ECS (NOVO)

OPÇÕES DE DEPLOY (modo tradicional):
    -f, --force             Força o build/deploy de todos os serviços
    -b, --build-only        Apenas constrói as imagens, não faz push
    -p, --push-only         Apenas faz push (assume que imagens já foram construídas)
    -s, --skip-health       Pula verificação de saúde (apenas verifica ECR)
    -j, --parallel          Executa builds em paralelo (experimental)
    -v, --verbose           Modo verboso
    -d, --dry-run           Apenas simula as ações sem executar
    --list-services         Lista todos os serviços disponíveis

ARGUMENTOS:
    SERVICE_NAME            Nome do serviço específico (opcional)

EXEMPLOS MODO ANÁLISE:
    $0                          # Gera matriz JSON dos serviços que precisam deploy
    $0 --output-file matrix.json # Salva análise em arquivo específico
    $0 --force --analyze-only   # Força análise de todos os serviços

EXEMPLOS MODO DEPLOY:
    $0 --build-only             # Deploy inteligente tradicional
    $0 front --build-only       # Deploy apenas do front se necessário
    $0 --force --build-only     # Força rebuild de todos os serviços

CORREÇÃO DE REDE:
    $0 --fix-network            # Corrige configuração de rede de todos os serviços
    $0 --fix-network --dry-run  # Simula correção de rede

VARIÁVEIS DE AMBIENTE:
    AWS_REGION              Região AWS (padrão: us-east-1)
    AWS_ACCOUNT_ID          ID da conta AWS
    PROJECT_NAME            Nome do projeto (padrão: kavoo)
    ENVIRONMENT             Ambiente (padrão: production)
    DOCKER_BUILDKIT         Habilita BuildKit (recomendado: 1)
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
            -a|--analyze-only)
                ANALYZE_ONLY=true
                shift
                ;;
            --output-file)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --output-format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --fix-network)
                # NOVA OPÇÃO: Corrigir rede
                check_dependencies
                if [[ -z "$AWS_ACCOUNT_ID" ]]; then
                    AWS_ACCOUNT_ID=$(aws_cmd sts get-caller-identity --query Account --output text)
                fi
                fix_all_services_network
                exit 0
                ;;
            -f|--force)
                FORCE_DEPLOY=true
                shift
                ;;
            -b|--build-only)
                BUILD_ONLY=true
                ANALYZE_ONLY=false  # Desativa modo análise
                shift
                ;;
            -p|--push-only)
                PUSH_ONLY=true
                ANALYZE_ONLY=false  # Desativa modo análise
                shift
                ;;
            -s|--skip-health)
                SKIP_HEALTH_CHECK=true
                shift
                ;;
            -j|--parallel)
                PARALLEL_BUILD=true
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
                if [[ -z "$TARGET_SERVICE" ]]; then
                    TARGET_SERVICE="$1"
                else
                    log_error "Múltiplos serviços especificados: $TARGET_SERVICE e $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

# Função para verificar dependências
check_dependencies() {
    local deps=("docker" "aws" "jq")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Dependências faltando: ${missing[*]}"
        exit 1
    fi
}

# Função para configurar Docker
setup_docker() {
    # Habilita BuildKit se não estiver configurado
    export DOCKER_BUILDKIT=1
    
    # Login no ECR
    if [[ "$DRY_RUN" == false ]]; then
        log "Fazendo login no ECR..."
        if ! aws_cmd ecr get-login-password | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"; then
            log_error "Falha no login do ECR"
            exit 1
        fi
        log_success "Login no ECR realizado com sucesso"
    fi
}

# Função para obter configuração do serviço
get_service_config() {
    local service_name="$1"
    
    case "$service_name" in
        "front")
            echo "apps/front Dockerfile 3000"
            ;;
        "admins-api")
            echo "apps/admins Dockerfile 8080"
            ;;
        "checkout-api")
            echo "apps/checkout Dockerfile 8081"
            ;;
        "members-api")
            echo "apps/members Dockerfile 8082"
            ;;
        "users-api")
            echo "apps/users Dockerfile 8083"
            ;;
        "webhooks-api")
            echo "apps/webhooks Dockerfile 8084"
            ;;
        *)
            log_error "Configuração não encontrada para serviço: $service_name"
            return 1
            ;;
    esac
}

# Função para construir uma imagem
build_image() {
    local service_name="$1"
    local config=($(get_service_config "$service_name"))
    local context_path="${PROJECT_ROOT}/${config[0]}"
    local dockerfile="${config[1]}"
    local port="${config[2]}"
    
    local image_tag="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}/${service_name}:latest"
    local build_args=()
    
    # Adiciona argumentos de build específicos por serviço
    case "$service_name" in
        "front")
            build_args+=("--build-arg" "NODE_ENV=${ENVIRONMENT}")
            build_args+=("--build-arg" "NEXT_TELEMETRY_DISABLED=1")
            ;;
        *"-api")
            build_args+=("--build-arg" "ENVIRONMENT=${ENVIRONMENT}")
            build_args+=("--build-arg" "PORT=${port}")
            ;;
    esac
    
    log "Construindo imagem: $service_name"
    if [[ "$VERBOSE" == true ]]; then
        log "  Context: $context_path"
        log "  Dockerfile: $dockerfile"
        log "  Tag: $image_tag"
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warning "DRY RUN: docker build seria executado"
        return 0
    fi
    
    # Constrói a imagem
    local build_start=$(date +%s)
    
    if docker build \
        --platform linux/amd64 \
        --tag "$image_tag" \
        --file "$context_path/$dockerfile" \
        "${build_args[@]}" \
        "$context_path"; then
        
        local build_end=$(date +%s)
        local build_time=$((build_end - build_start))
        
        log_success "Imagem construída em ${build_time}s: $service_name"
        ((BUILD_COUNT++))
        return 0
    else
        log_error "Falha na construção da imagem: $service_name"
        ((ERROR_COUNT++))
        return 1
    fi
}

# Função para fazer push da imagem
push_image() {
    local service_name="$1"
    local image_tag="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}/${service_name}:latest"
    
    log "Fazendo push da imagem: $service_name"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warning "DRY RUN: docker push seria executado"
        return 0
    fi
    
    # Garante que o repositório existe
    local repo_name="${PROJECT_NAME}/${service_name}"
    if ! aws_cmd ecr describe-repositories --repository-names "$repo_name" &> /dev/null; then
        log "Criando repositório ECR: $repo_name"
        if ! aws_cmd ecr create-repository --repository-name "$repo_name" &> /dev/null; then
            log_error "Falha ao criar repositório ECR: $repo_name"
            return 1
        fi
    fi
    
    local push_start=$(date +%s)
    
    if docker push "$image_tag"; then
        local push_end=$(date +%s)
        local push_time=$((push_end - push_start))
        
        log_success "Push realizado em ${push_time}s: $service_name"
        ((PUSH_COUNT++))
        return 0
    else
        log_error "Falha no push da imagem: $service_name"
        ((ERROR_COUNT++))
        return 1
    fi
}

# Função para processar um serviço
process_service() {
    local service_name="$1"
    local force_build="${2:-false}"
    
    log "=== Processando serviço: $service_name ==="
    
    # Verifica se precisa de deploy (se não for forçado)
    if [[ "$force_build" == false ]] && [[ "$FORCE_DEPLOY" == false ]]; then
        local check_args=()
        [[ "$SKIP_HEALTH_CHECK" == true ]] && check_args+=("--check-ecr")
        [[ "$VERBOSE" == true ]] && check_args+=("--verbose")
        
        if "${SCRIPT_DIR}/check-image-health.sh" "${check_args[@]}" "$service_name" > /dev/null 2>&1; then
            log_success "Serviço $service_name não precisa de deploy - pulando"
            ((SKIP_COUNT++))
            return 0
        else
            log_warning "Serviço $service_name precisa de deploy"
        fi
    fi
    
    # Executa build se não for push-only
    if [[ "$PUSH_ONLY" == false ]]; then
        if ! build_image "$service_name"; then
            return 1
        fi
    fi
    
    # Executa push se não for build-only
    if [[ "$BUILD_ONLY" == false ]]; then
        if ! push_image "$service_name"; then
            return 1
        fi
    fi
    
    return 0
}

# Função para processar serviços em paralelo
process_services_parallel() {
    local services=("$@")
    local pids=()
    local results=()
    
    log "Iniciando build paralelo de ${#services[@]} serviços..."
    
    # Inicia processos em background
    for service in "${services[@]}"; do
        (
            if process_service "$service"; then
                echo "SUCCESS:$service"
            else
                echo "FAILURE:$service"
            fi
        ) &
        pids+=($!)
    done
    
    # Aguarda todos os processos
    for i in "${!pids[@]}"; do
        wait "${pids[$i]}"
        local result=$(jobs -p | grep -q "${pids[$i]}" && echo "RUNNING" || echo "FINISHED")
        results+=("$result")
    done
    
    log_success "Build paralelo concluído"
}

# Função principal
main() {
    parse_args "$@"
    
    log "Iniciando deploy inteligente..."
    log "Projeto: $PROJECT_NAME | Ambiente: $ENVIRONMENT"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warning "Modo DRY RUN - Nenhuma ação será executada"
    fi
    
    # Por padrão, usa modo análise se não especificado explicitamente
    if [[ "$BUILD_ONLY" == false ]] && [[ "$PUSH_ONLY" == false ]]; then
        ANALYZE_ONLY=true
    fi
    
    # Modo análise - gera matriz JSON e sai
    if [[ "$ANALYZE_ONLY" == true ]]; then
        log "=== MODO ANÁLISE ATIVADO ==="
        
        check_dependencies
        
        # Configura AWS Account ID se não estiver definido
        if [[ -z "$AWS_ACCOUNT_ID" ]]; then
            log "Obtendo AWS Account ID..."
            AWS_ACCOUNT_ID=$(aws_cmd sts get-caller-identity --query Account --output text)
        fi
        
        analyze_services
        return 0
    fi

    # Modo deploy tradicional
    log "=== MODO DEPLOY TRADICIONAL ==="
    
    if [[ "$FORCE_DEPLOY" == true ]]; then
        log_warning "Deploy forçado - Todos os serviços serão processados"
    fi

    check_dependencies
    
    # Configura AWS Account ID se não estiver definido
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        log "Obtendo AWS Account ID..."
        AWS_ACCOUNT_ID=$(aws_cmd sts get-caller-identity --query Account --output text)
    fi
    
    setup_docker

    # Determina quais serviços processar
    local services_to_process=()
    if [[ -n "$TARGET_SERVICE" ]]; then
        if [[ ! " ${SERVICES[*]} " =~ " $TARGET_SERVICE " ]]; then
            log_error "Serviço não encontrado: $TARGET_SERVICE"
            log "Serviços disponíveis: ${SERVICES[*]}"
            exit 1
        fi
        services_to_process=("$TARGET_SERVICE")
    else
        services_to_process=("${SERVICES[@]}")
    fi

    # Processa serviços
    local start_time=$(date +%s)
    
    if [[ "$PARALLEL_BUILD" == true ]] && [[ ${#services_to_process[@]} -gt 1 ]]; then
        process_services_parallel "${services_to_process[@]}"
    else
        for service in "${services_to_process[@]}"; do
            if ! process_service "$service"; then
                log_error "Falha no processamento do serviço: $service"
            fi
            echo
        done
    fi
    
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))

    # Estatísticas finais
    log "=== ESTATÍSTICAS ==="
    log "Tempo total: ${total_time}s"
    log_success "Builds realizados: $BUILD_COUNT"
    log_success "Pushes realizados: $PUSH_COUNT"
    log_success "Serviços pulados: $SKIP_COUNT"
    
    if [[ $ERROR_COUNT -gt 0 ]]; then
        log_error "Erros encontrados: $ERROR_COUNT"
        exit 1
    else
        log_success "Deploy inteligente concluído com sucesso!"
        
        # Atualiza terraform se houver novos pushes
        if [[ $PUSH_COUNT -gt 0 ]] && [[ "$BUILD_ONLY" == false ]]; then
            log "Novas imagens foram enviadas - considere executar 'terraform apply' para atualizar os serviços ECS"
        fi
        
        exit 0
    fi
}

# NOVA FUNÇÃO: Verificar e corrigir configuração de rede
check_and_fix_network_config() {
    local service_name="$1"
    
    log "Verificando configuração de rede para $service_name..."
    
    # Obter configuração atual do serviço
    local service_config
    if ! service_config=$(aws_cmd ecs describe-services \
        --cluster "${PROJECT_NAME}-cluster" \
        --services "${PROJECT_NAME}-$service_name" \
        --query 'services[0].networkConfiguration.awsvpcConfiguration' \
        --output json 2>/dev/null); then
        log_warning "Serviço $service_name não encontrado ou sem configuração de rede"
        return 0  # Não há problema se serviço não existe ainda
    fi
    
    if [[ -n "$service_config" && "$service_config" != "null" ]]; then
        local assign_public_ip=$(echo "$service_config" | jq -r '.assignPublicIp // "DISABLED"')
        
        # Verificar se está usando IP público desabilitado (problema potencial)
        if [[ "$assign_public_ip" == "DISABLED" ]]; then
            log_warning "Serviço $service_name com assignPublicIp=DISABLED pode ter problemas de conectividade"
            return 1  # Indica que precisa de correção
        fi
    fi
    
    return 0
}

# NOVA FUNÇÃO: Aplicar correção de rede automática
apply_network_fix() {
    local service_name="$1"
    
    log "=== APLICANDO CORREÇÃO DE REDE PARA $service_name ==="
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warning "DRY RUN: correção de rede seria aplicada para $service_name"
        return 0
    fi
    
    # Obter subnets públicas disponíveis
    local public_subnets
    if ! public_subnets=$(aws_cmd ec2 describe-subnets \
        --filters "Name=tag:Name,Values=*public*" \
        --query 'Subnets[0:2].SubnetId' \
        --output text 2>/dev/null); then
        log_error "Não foi possível encontrar subnets públicas"
        return 1
    fi
    
    # Converter para array JSON
    local subnet_array="[]"
    for subnet in $public_subnets; do
        subnet_array=$(echo "$subnet_array" | jq --arg subnet "$subnet" '. += [$subnet]')
    done
    
    # Obter security group atual
    local current_sg
    if ! current_sg=$(aws_cmd ecs describe-services \
        --cluster "${PROJECT_NAME}-cluster" \
        --services "${PROJECT_NAME}-$service_name" \
        --query 'services[0].networkConfiguration.awsvpcConfiguration.securityGroups[0]' \
        --output text 2>/dev/null); then
        log_error "Não foi possível obter security group atual"
        return 1
    fi
    
    # Aplicar correção de rede
    log "Atualizando configuração de rede do serviço ${PROJECT_NAME}-$service_name..."
    
    local network_config=$(jq -n \
        --argjson subnets "$subnet_array" \
        --arg sg "$current_sg" \
        '{
            awsvpcConfiguration: {
                subnets: $subnets,
                securityGroups: [$sg],
                assignPublicIp: "ENABLED"
            }
        }')
    
    if aws_cmd ecs update-service \
        --cluster "${PROJECT_NAME}-cluster" \
        --service "${PROJECT_NAME}-$service_name" \
        --network-configuration "$network_config" \
        --force-new-deployment > /dev/null; then
        
        log_success "Configuração de rede corrigida para $service_name"
        
        # Aguardar alguns segundos para que as mudanças tenham efeito
        log "Aguardando aplicação das mudanças..."
        sleep 15
        
        return 0
    else
        log_error "Falha na correção de rede para $service_name"
        return 1
    fi
}

# NOVA FUNÇÃO: Comando para correção manual
fix_all_services_network() {
    log "=== CORRIGINDO REDE DE TODOS OS SERVIÇOS ==="
    
    local fixed_count=0
    local error_count=0
    
    for service in "${SERVICES[@]}"; do
        log "Verificando $service..."
        
        # Verifica se o serviço existe
        if aws_cmd ecs describe-services --cluster "${PROJECT_NAME}-cluster" --services "${PROJECT_NAME}-$service" > /dev/null 2>&1; then
            if ! check_and_fix_network_config "$service"; then
                if apply_network_fix "$service"; then
                    ((fixed_count++))
                    log_success "✅ $service: rede corrigida"
                else
                    ((error_count++))
                    log_error "❌ $service: falha na correção"
                fi
            else
                log_success "✅ $service: rede já está correta"
            fi
        else
            log "⚪ $service: serviço não existe (ok)"
        fi
        
        echo
    done
    
    log "=== RESUMO DA CORREÇÃO ==="
    log_success "Serviços corrigidos: $fixed_count"
    log_error "Erros encontrados: $error_count"
    
    if [[ $error_count -eq 0 ]]; then
        log_success "Todos os serviços foram verificados/corrigidos!"
    fi
}

# Executa apenas se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi