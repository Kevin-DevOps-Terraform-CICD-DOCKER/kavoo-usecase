#!/bin/bash

#
# Script para visualizar o status das imagens ECR dos serviços
# Mostra quantas imagens cada repositório tem e suas tags mais recentes
#

set -euo pipefail

# Configurações
AWS_PROFILE="${AWS_PROFILE:-kavoo}"
REGION="${AWS_REGION:-us-east-1}"

# Lista de serviços/repositórios
SERVICES=(
    "kavoo/admins-api"
    "kavoo/checkout-api" 
    "kavoo/front"
    "kavoo/members-api"
    "kavoo/users-api"
    "kavoo/webhooks-api"
)

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Função para log colorido
log() {
    local level=$1
    shift
    case $level in
        INFO)  echo -e "${BLUE}[INFO]${NC} $*" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $*" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $*" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $*" ;;
    esac
}

# Função para formatar tamanho de imagem
format_size() {
    local bytes=$1
    if [[ $bytes -gt 1073741824 ]]; then
        echo "$(( bytes / 1073741824 ))GB"
    elif [[ $bytes -gt 1048576 ]]; then
        echo "$(( bytes / 1048576 ))MB"
    elif [[ $bytes -gt 1024 ]]; then
        echo "$(( bytes / 1024 ))KB"
    else
        echo "${bytes}B"
    fi
}

# Função para mostrar informações de um repositório
show_repository_info() {
    local repo_name=$1
    
    if ! aws ecr describe-repositories \
        --repository-names "$repo_name" \
        --region "$REGION" \
        --profile "$AWS_PROFILE" \
        --output text > /dev/null 2>&1; then
        printf "%-20s %s\n" "$repo_name" "${RED}[NOT FOUND]${NC}"
        return
    fi
    
    # Obter informações das imagens
    local images_info
    images_info=$(aws ecr describe-images \
        --repository-name "$repo_name" \
        --region "$REGION" \
        --profile "$AWS_PROFILE" \
        --query 'imageDetails[*].[imagePushedAt,imageSizeInBytes,imageTags[0]]' \
        --output text | sort -r)
    
    if [[ -z "$images_info" ]]; then
        printf "%-20s %s\n" "$repo_name" "${YELLOW}[EMPTY]${NC}"
        return
    fi
    
    local total_images
    total_images=$(echo "$images_info" | wc -l)
    
    # Calcular tamanho total
    local total_size=0
    while IFS=$'\t' read -r pushed_at size_bytes tag; do
        if [[ -n "$size_bytes" && "$size_bytes" != "None" ]]; then
            total_size=$((total_size + size_bytes))
        fi
    done <<< "$images_info"
    
    # Pegar as 3 imagens mais recentes para mostrar
    local recent_images
    recent_images=$(echo "$images_info" | head -3)
    
    printf "%-20s ${GREEN}%2d images${NC} (${CYAN}%s${NC})\n" \
        "$repo_name" \
        "$total_images" \
        "$(format_size $total_size)"
    
    # Mostrar as 3 mais recentes
    echo "$recent_images" | while IFS=$'\t' read -r pushed_at size_bytes tag; do
        local tag_display="$tag"
        if [[ -z "$tag" || "$tag" == "None" ]]; then
            tag_display="${YELLOW}[no-tag]${NC}"
        fi
        
        local date_display
        date_display=$(date -d "$pushed_at" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$pushed_at")
        
        printf "    └─ %-40s ${BLUE}%s${NC} (${CYAN}%s${NC})\n" \
            "$tag_display" \
            "$date_display" \
            "$(format_size $size_bytes)"
    done
    
    if [[ $total_images -gt 3 ]]; then
        printf "    ${YELLOW}... and %d more images${NC}\n" $((total_images - 3))
    fi
    
    echo
}

# Função principal
main() {
    echo -e "${BLUE}====== ECR Images Status ======${NC}"
    echo -e "AWS Profile: ${YELLOW}$AWS_PROFILE${NC}"
    echo -e "Region: ${YELLOW}$REGION${NC}"
    echo
    
    # Verificar credenciais AWS
    if ! aws sts get-caller-identity --profile "$AWS_PROFILE" > /dev/null 2>&1; then
        log ERROR "Falha na autenticação AWS com profile '$AWS_PROFILE'"
        log ERROR "Verifique suas credenciais e tente novamente"
        exit 1
    fi
    
    # Mostrar informações de cada repositório
    for service in "${SERVICES[@]}"; do
        show_repository_info "$service"
    done
    
    # Mostrar resumo de limpeza recomendada
    echo -e "${BLUE}====== Cleanup Recommendations ======${NC}"
    echo "Para limpar imagens antigas:"
    echo -e "  ${CYAN}./scripts/cleanup-ecr-images.sh --dry-run${NC}     # Ver o que seria deletado"
    echo -e "  ${CYAN}./scripts/cleanup-ecr-images.sh --keep 3${NC}      # Manter apenas 3 imagens"
    echo -e "  ${CYAN}./scripts/cleanup-ecr-images.sh --keep 5${NC}      # Manter apenas 5 imagens"
    echo
}

# Função de ajuda
show_help() {
    cat << EOF
Script para visualizar o status das imagens ECR dos serviços Kavoo

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help          Mostra esta ajuda
    -p, --profile NAME  AWS profile a usar (padrão: kavoo)
    -r, --region NAME   AWS region (padrão: us-east-1)

EXAMPLES:
    # Mostrar status com configurações padrão
    $0
    
    # Usar profile diferente
    $0 --profile production

REPOSITORIES MONITORED:
EOF
    printf "    - %s\n" "${SERVICES[@]}"
}

# Parse de argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -p|--profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        *)
            log ERROR "Opção desconhecida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Executar função principal
main