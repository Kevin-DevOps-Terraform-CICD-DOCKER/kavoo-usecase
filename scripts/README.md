
## Scripts essenciais (Nao deletar)

check-image-health.sh
cleanup-ecr-images.sh         # Limpeza de imagens antigas no ECR
cleanup-ecr-complete.sh       # Limpeza COMPLETA de todas as imagens (DESTRUTIVO)
ecr-images-status.sh          # Visualização do status das imagens ECR
generate-deploy-matrix.sh
smart-deploy.sh

## Scripts de Gerenciamento ECR

### ecr-images-status.sh
Visualiza o status atual das imagens em todos os repositórios ECR dos serviços.

**Uso:**
```bash
./scripts/ecr-images-status.sh                    # Status completo
./scripts/ecr-images-status.sh --profile prod     # Com profile específico
```

### cleanup-ecr-images.sh
Remove imagens antigas dos repositórios ECR, mantendo apenas as N mais recentes.

**Uso:**
```bash
./scripts/cleanup-ecr-images.sh --dry-run         # Ver o que seria deletado
./scripts/cleanup-ecr-images.sh --keep 3          # Manter apenas 3 imagens
./scripts/cleanup-ecr-images.sh --keep 5          # Manter apenas 5 imagens (padrão)
./scripts/cleanup-ecr-images.sh --keep 0 --dry-run # Ver todas as imagens que seriam deletadas
./scripts/cleanup-ecr-images.sh --keep 0          # DELETAR TODAS as imagens
```

### cleanup-ecr-complete.sh ⚠️ 
**OPERAÇÃO DESTRUTIVA** - Remove TODAS as imagens de TODOS os repositórios ECR.

**Características de Segurança:**
- Preview completo antes da execução
- Dupla confirmação necessária
- Frases específicas devem ser digitadas
- Não pode ser executado acidentalmente

**Uso:**
```bash
./scripts/cleanup-ecr-complete.sh                 # Limpeza completa com confirmações
./scripts/cleanup-ecr-complete.sh --profile prod  # Com profile específico
```

**⚠️ IMPORTANTE:** Esta operação torna impossível fazer rollback para versões anteriores!

**Repositórios gerenciados:**
- kavoo/admins-api
- kavoo/checkout-api
- kavoo/front
- kavoo/members-api
- kavoo/users-api
- kavoo/webhooks-api

