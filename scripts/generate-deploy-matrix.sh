#!/bin/bash



set -euo pipefail

# Configurações
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
ANALYSIS_FILE="${PROJECT_ROOT}/deploy-matrix.json"
OUTPUT_FORMAT="github"  # github | json | matrix-only
INPUT_FILE=""

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗${NC} $1" >&2
}

show_help() {
    cat << EOF
Uso: $0 [OPTIONS]

Gera matriz dinâmica para GitHub Actions baseada na análise do smart-deploy.

OPÇÕES:
    -h, --help              Mostra esta ajuda
    -i, --input FILE        Arquivo JSON de entrada (padrão: deploy-matrix.json)
    -f, --format FORMAT     Formato de saída (github|json|matrix-only) (padrão: github)

FORMATOS DE SAÍDA:
    github      - Saída formatada para GitHub Actions outputs
    json        - JSON completo com todas as informações
    matrix-only - Apenas a matriz de serviços

EXEMPLOS:
    $0                                      # Gera matriz para GitHub Actions
    $0 --format json                       # Mostra JSON completo
    $0 --input custom-matrix.json          # Usa arquivo personalizado
    $0 --format matrix-only                # Apenas lista de serviços

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -i|--input)
                INPUT_FILE="$2"
                shift 2
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            *)
                log_error "Argumento desconhecido: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

generate_github_matrix() {
    local analysis_file="$1"
    
    if [[ ! -f "$analysis_file" ]]; then
        log_error "Arquivo de análise não encontrado: $analysis_file"
        log "Execute primeiro: ./smart-deploy.sh --analyze-only"
        exit 1
    fi
    
    log "Processando análise de: $analysis_file"
    
    # Verifica se arquivo tem conteúdo válido
    if ! jq empty "$analysis_file" 2>/dev/null; then
        log_error "Arquivo JSON inválido: $analysis_file"
        exit 1
    fi
    
    # Extrai serviços que precisam de deploy
    local services_needing_deploy=$(jq -r '.services[] | select(.needs_deploy == true) | .name' "$analysis_file")
    local all_services=$(jq -r '.services[].name' "$analysis_file")
    local needs_deploy_count=$(jq -r '.summary.needs_deploy' "$analysis_file")
    local healthy_count=$(jq -r '.summary.already_healthy' "$analysis_file")
    
    log "Resumo da análise:"
    log "  - Total de serviços: $(jq -r '.summary.total_services' "$analysis_file")"
    log_warning "  - Precisam de deploy: $needs_deploy_count"
    log_success "  - Já saudáveis: $healthy_count"
    
    case "$OUTPUT_FORMAT" in
        github)
            generate_github_output "$analysis_file"
            ;;
        json)
            jq '.' "$analysis_file"
            ;;
        matrix-only)
            if [[ -n "$services_needing_deploy" ]]; then
                echo "$services_needing_deploy" | jq -R -s 'split("\n") | map(select(. != ""))'
            else
                echo '[]'
            fi
            ;;
        *)
            log_error "Formato de saída inválido: $OUTPUT_FORMAT"
            exit 1
            ;;
    esac
}

generate_github_output() {
    local analysis_file="$1"
    
    # Gera outputs para GitHub Actions
    local services_needing_deploy=$(jq -r '.services[] | select(.needs_deploy == true) | .name' "$analysis_file")
    local needs_deploy_count=$(jq -r '.summary.needs_deploy' "$analysis_file")
    
    # Converte para array JSON (compacto, uma única linha)
    local services_matrix
    if [[ -n "$services_needing_deploy" ]]; then
        services_matrix=$(echo "$services_needing_deploy" | jq -R -s -c 'split("\n") | map(select(. != ""))')
    else
        services_matrix='[]'
    fi
    
    # Gera outputs do GitHub Actions
    echo "services-matrix=$services_matrix"
    echo "needs-deploy=$([[ "$needs_deploy_count" -gt 0 ]] && echo "true" || echo "false")"
    echo "deploy-count=$needs_deploy_count"
    
    # Outputs individuais para cada serviço
    for service in $(jq -r '.services[].name' "$analysis_file"); do
        local needs_deploy=$(jq -r ".services[] | select(.name == \"$service\") | .needs_deploy" "$analysis_file")
        local reason=$(jq -r ".services[] | select(.name == \"$service\") | .reason" "$analysis_file")
        
        echo "${service}-needs-deploy=${needs_deploy}"
        echo "${service}-reason=${reason}"
    done
    
    # Status geral
    local timestamp=$(jq -r '.summary.timestamp' "$analysis_file")
    echo "analysis-timestamp=${timestamp}"
    
    # Informações adicionais para debug
    echo "analysis-summary=$(jq -c '.summary' "$analysis_file")"
}

main() {
    parse_args "$@"
    
    # Define arquivo padrão se não especificado
    if [[ -z "$INPUT_FILE" ]]; then
        INPUT_FILE="$ANALYSIS_FILE"
    fi
    
    log "=== Gerador de Matriz de Deploy ==="
    log "Arquivo de entrada: $INPUT_FILE"
    log "Formato de saída: $OUTPUT_FORMAT"
    
    generate_github_matrix "$INPUT_FILE"
}

# Executa apenas se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi