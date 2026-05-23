#!/usr/bin/env bash
# init.git.sh — Inicializa o repositório Git da pasta Emulador/ e publica no GitHub.
#
# Opera EXCLUSIVAMENTE sobre a pasta Emulador/ (a pasta pai deste script),
# independentemente do repositório Git "wrapper" que possa existir acima.
#
# Uso:
#   ./init.git.sh                                  # usa o remoto padrão
#   ./init.git.sh <url-do-repositorio> [branch]    # remoto customizado
#
# Exemplos:
#   ./init.git.sh
#   ./init.git.sh git@github.com:fmiozzi/teoria-computacao-artigo-emulador.git
#   ./init.git.sh https://github.com/fmiozzi/teoria-computacao-artigo-emulador.git develop
#
# Pré-requisitos:
#   - git instalado
#   - Repositório criado no GitHub (vazio, sem README/commits)
#   - Chave SSH configurada (se usar git@) ou token HTTPS configurado

set -euo pipefail

# Remoto padrão deste projeto (Emulador).
DEFAULT_REMOTE_URL="https://github.com/fmiozzi/teoria-computacao-artigo-emulador.git"

# =============================
# Cores e helpers de output
# =============================

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}ℹ️  $*${RESET}"; }
success() { echo -e "${GREEN}${BOLD}✅ $*${RESET}"; }
warn()    { echo -e "${YELLOW}${BOLD}⚠️  $*${RESET}"; }
error()   { echo -e "${RED}${BOLD}❌ $*${RESET}"; }
step()    { echo -e "\n${BLUE}${BOLD}── $* ${RESET}"; }

# =============================
# Argumentos
# =============================

REMOTE_URL="${1:-$DEFAULT_REMOTE_URL}"
BRANCH="${2:-main}"

if [ "$REMOTE_URL" = "$DEFAULT_REMOTE_URL" ]; then
    info "Usando remoto padrão: $DEFAULT_REMOTE_URL"
    info "(passe outra URL como 1º argumento para sobrescrever)"
fi

# =============================
# Detecta o diretório do projeto
# (sempre relativo ao local do script, não ao pwd do chamador)
# =============================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo -e "${BOLD}🚀 Inicializando repositório Git (apenas pasta Emulador/)${RESET}"
echo -e "   Diretório : ${CYAN}$SCRIPT_DIR${RESET}"
echo -e "   Remote    : ${CYAN}$REMOTE_URL${RESET}"
echo -e "   Branch    : ${CYAN}$BRANCH${RESET}"
echo ""

# =============================
# Avisa se Emulador/ está dentro de outro repo Git (situação transitória)
# =============================

PARENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if (cd "$PARENT_DIR" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
    OUTER_ROOT="$(cd "$PARENT_DIR" && git rev-parse --show-toplevel)"
    if [ "$OUTER_ROOT" != "$SCRIPT_DIR" ]; then
        warn "A pasta Emulador/ está dentro de outro repositório Git:"
        warn "  $OUTER_ROOT"
        warn "Será criado um .git INDEPENDENTE em $SCRIPT_DIR/.git"
        warn "(o repo externo passará a ver Emulador/ como submódulo — esperado)"
    fi
fi

# =============================
# Verifica pré-requisitos
# =============================

step "Verificando pré-requisitos"

# Verifica se git está instalado
if ! command -v git &> /dev/null; then
    error "git não encontrado. Instale com: sudo apt install git"
    exit 1
fi
success "git $(git --version | awk '{print $3}') encontrado"

# Verifica se git user está configurado (necessário para commits)
GIT_USER=$(git config --global user.name 2>/dev/null || echo "")
GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

if [ -z "$GIT_USER" ] || [ -z "$GIT_EMAIL" ]; then
    error "Identidade Git não configurada."
    echo ""
    echo -e "${BOLD}Configure com:${RESET}"
    echo -e "  ${CYAN}git config --global user.name  \"Seu Nome\"${RESET}"
    echo -e "  ${CYAN}git config --global user.email \"seu@email.com\"${RESET}"
    exit 1
fi
success "Identidade: $GIT_USER <$GIT_EMAIL>"

# Testa conectividade com o remoto (sem autenticar, só resolve o host)
REMOTE_HOST=$(echo "$REMOTE_URL" | sed -E 's|.*@([^:/]+).*|\1|; s|https?://([^/]+).*|\1|')
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$REMOTE_HOST" exit 2>/dev/null; then
    # SSH falhou — pode ser normal para HTTPS ou pode ser problema de chave
    if [[ "$REMOTE_URL" == git@* ]]; then
        warn "Não foi possível verificar conectividade SSH com $REMOTE_HOST"
        warn "Certifique-se de que sua chave SSH está adicionada ao GitHub"
        warn "Teste com: ssh -T git@github.com"
        # Não abortamos aqui — o push vai revelar o erro com mensagem clara
    fi
fi

# =============================
# Inicializa o repositório local
# =============================

step "Repositório local"

if [ -d ".git" ]; then
    warn "Já existe um repositório Git neste diretório."
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    info "Branch atual: ${CURRENT_BRANCH:-desconhecida}"

    # Verifica se já tem commits
    if git log --oneline -1 &>/dev/null; then
        warn "Já existem commits. O init.git.sh é para repositórios novos."
        echo -e "  Para sincronizar um repo existente use: ${CYAN}./sync.git.sh${RESET}"
        echo ""
        read -rp "Deseja continuar mesmo assim? (s/N): " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[sS]$ ]]; then
            info "Operação cancelada."
            exit 0
        fi
    fi
else
    git init
    success "Repositório Git inicializado em .git/"
fi

# Garante que HEAD aponta para a branch desejada.
# Em repo recém-criado (sem commits), 'git checkout -b' falha em algumas versões;
# 'git symbolic-ref' funciona com ou sem commits.
if git rev-parse --verify HEAD >/dev/null 2>&1; then
    # Já há commits: usa branch -M para renomear se necessário
    CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
    if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
        git branch -M "$BRANCH"
    fi
else
    # Repo vazio: aponta HEAD para refs/heads/$BRANCH diretamente
    git symbolic-ref HEAD "refs/heads/$BRANCH"
fi
success "Branch: $BRANCH"

# =============================
# Configura o .gitignore se não existir
# =============================

step "Configuração do .gitignore"

if [ ! -f ".gitignore" ]; then
    warn ".gitignore não encontrado — criando um básico..."
    cat > .gitignore << 'EOF'
# Build / compilação
dist-newstyle/
.stack-work/
*.o
*.hi
*.dyn_o
*.dyn_hi

# Binários gerados
result

# Temporários
*.tmp
*.bak
*~

# Ambiente
.env
.env.local

# Editor
.vscode/
.idea/
*.swp
EOF
    success ".gitignore criado"
else
    success ".gitignore já existe"
fi

# =============================
# Adiciona todos os arquivos ao stage
# (novos, modificados; remove deletados do índice)
# =============================

step "Preparando arquivos"

git add -A

# Conta e exibe o que foi adicionado
STAGED_COUNT=$(git diff --cached --name-only | wc -l)

if [ "$STAGED_COUNT" -eq 0 ]; then
    warn "Nenhum arquivo para commitar."
    info "Certifique-se de que o diretório tem conteúdo."
    exit 0
fi

echo ""
echo -e "${BOLD}Arquivos que serão commitados ($STAGED_COUNT):${RESET}"
git diff --cached --stat | sed 's/^/  /'
echo ""

# =============================
# Commit inicial
# =============================

step "Commit inicial"

COMMIT_MSG="init: $(basename "$SCRIPT_DIR") — $(date '+%Y-%m-%d %H:%M:%S')"

if ! git commit -m "$COMMIT_MSG"; then
    error "Falha ao criar o commit inicial."
    echo ""
    echo -e "${BOLD}Possíveis causas:${RESET}"
    echo -e "  • Identidade Git não configurada (user.name / user.email)"
    echo -e "  • Hook de pre-commit bloqueando o commit"
    echo -e "  • Nenhum arquivo staged"
    exit 1
fi
success "Commit criado: \"$COMMIT_MSG\""

# =============================
# Configura o remote origin
# =============================

step "Remote origin"

if git remote get-url origin &>/dev/null; then
    EXISTING_URL=$(git remote get-url origin)
    if [ "$EXISTING_URL" = "$REMOTE_URL" ]; then
        success "Remote origin já configurado: $EXISTING_URL"
    else
        warn "Remote origin existe com URL diferente:"
        echo -e "  Atual  : ${YELLOW}$EXISTING_URL${RESET}"
        echo -e "  Novo   : ${CYAN}$REMOTE_URL${RESET}"
        echo ""
        read -rp "Substituir o remote? (s/N): " CONFIRM
        if [[ "$CONFIRM" =~ ^[sS]$ ]]; then
            git remote set-url origin "$REMOTE_URL"
            success "Remote atualizado para: $REMOTE_URL"
        else
            warn "Remote mantido: $EXISTING_URL"
        fi
    fi
else
    git remote add origin "$REMOTE_URL"
    success "Remote adicionado: $REMOTE_URL"
fi

# =============================
# Push para o GitHub
# =============================

step "Push para o GitHub"

info "Enviando branch '$BRANCH' para origin..."
echo ""

if ! git push -u origin "$BRANCH" 2>&1; then
    echo ""
    error "=========================================="
    error "  FALHA NO PUSH"
    error "=========================================="
    echo ""

    # Diagnóstico baseado na URL
    if [[ "$REMOTE_URL" == git@* ]]; then
        echo -e "${BOLD}Possíveis causas (SSH):${RESET}"
        echo -e "  ${RED}•${RESET} Chave SSH não adicionada ao GitHub"
        echo -e "    → Teste: ${CYAN}ssh -T git@github.com${RESET}"
        echo -e "    → Adicione em: https://github.com/settings/keys"
        echo -e "  ${RED}•${RESET} Repositório não existe ou nome incorreto"
        echo -e "    → URL usada: ${CYAN}$REMOTE_URL${RESET}"
        echo -e "    → Crie em  : https://github.com/new"
        echo -e "  ${RED}•${RESET} Repositório remoto não está vazio"
        echo -e "    → Se já tem commits remotos, use: ${CYAN}./sync.git.sh${RESET}"
    else
        echo -e "${BOLD}Possíveis causas (HTTPS):${RESET}"
        echo -e "  ${RED}•${RESET} Token de acesso expirado ou sem permissão de escrita"
        echo -e "    → Gere em: https://github.com/settings/tokens"
        echo -e "  ${RED}•${RESET} Repositório não existe ou URL incorreta"
        echo -e "    → URL usada: ${CYAN}$REMOTE_URL${RESET}"
        echo -e "  ${RED}•${RESET} Repositório remoto não está vazio"
        echo -e "    → Se já tem commits remotos, use: ${CYAN}./sync.git.sh${RESET}"
    fi

    echo ""
    echo -e "${BOLD}Estado atual do repositório local:${RESET}"
    git log --oneline -3 | sed 's/^/  /'
    echo ""
    echo -e "  O commit foi criado localmente. Execute o push manualmente quando resolver:"
    echo -e "  ${CYAN}git push -u origin $BRANCH${RESET}"
    echo ""
    exit 1
fi

# =============================
# Resumo final
# =============================

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║   🎉  Repositório publicado com sucesso!  ║${RESET}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  Branch  : ${CYAN}$BRANCH${RESET}"
echo -e "  Remote  : ${CYAN}$REMOTE_URL${RESET}"
echo -e "  Commits : $(git rev-list --count HEAD)"
echo -e "  Arquivos: $STAGED_COUNT"
echo ""
echo -e "  Para sincronizar no futuro: ${CYAN}./sync.git.sh${RESET}"
echo ""
