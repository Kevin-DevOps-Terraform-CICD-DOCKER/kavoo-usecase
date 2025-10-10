#!/bin/bash

# Script SUPER SIMPLES para deletar imagens ECR
# Sem loops complexos, sem pipes problemáticos

AWS_PROFILE="kavoo"
REGION="us-east-1"
DRY_RUN="${1:-true}"

echo "=== SCRIPT SIMPLES PARA DELETAR IMAGENS ECR ==="
echo "Profile: $AWS_PROFILE | Region: $REGION"
echo "Modo: $([ "$DRY_RUN" = "true" ] && echo "DRY RUN" || echo "EXECUÇÃO REAL")"
echo

# Função para processar um repositório
process_repo() {
    local repo="$1"
    echo "📂 $repo"
    
    # Verificar se existe
    if ! aws ecr describe-repositories --repository-names "$repo" --profile "$AWS_PROFILE" --region "$REGION" >/dev/null 2>&1; then
        echo "   ❌ Repositório não encontrado"
        return 0
    fi
    
    # Contar imagens
    local count
    count=$(aws ecr describe-images --repository-name "$repo" --profile "$AWS_PROFILE" --region "$REGION" --query 'length(imageDetails)' --output text 2>/dev/null || echo "0")
    
    echo "   📊 $count imagens encontradas"
    
    if [ "$count" = "0" ]; then
        echo "   ✅ Repositório vazio"
        return 0
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
        echo "   🔍 [DRY RUN] Deletaria $count imagens"
    else
        echo "   🗑️  Deletando $count imagens..."
        # Deletar todas as imagens de uma vez
        if aws ecr list-images --repository-name "$repo" --profile "$AWS_PROFILE" --region "$REGION" --query 'imageIds[*]' --output json | \
           aws ecr batch-delete-image --repository-name "$repo" --profile "$AWS_PROFILE" --region "$REGION" --image-ids file:///dev/stdin >/dev/null 2>&1; then
            echo "   ✅ Imagens deletadas com sucesso"
        else
            echo "   ❌ Erro ao deletar imagens"
        fi
    fi
    
    echo
}

# Processar repositórios um por um
process_repo "kavoo/admins-api"
process_repo "kavoo/checkout-api"  
process_repo "kavoo/front"
process_repo "kavoo/members-api"
process_repo "kavoo/users-api"
process_repo "kavoo/webhooks-api"

echo "=== CONCLUÍDO ==="

if [ "$DRY_RUN" = "true" ]; then
    echo "Para executar REALMENTE: $0 false"
fi