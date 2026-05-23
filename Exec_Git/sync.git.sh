#!/usr/bin/env bash
# sync.git.sh — Sincroniza APENAS a pasta Emulador/ com o GitHub.
#
# Opera exclusivamente sobre Emulador/ (pasta pai deste script) — usa o
# .git da própria Emulador, não um repositório "wrapper" acima.
# Inclui arquivos novos, atualiza modificados e remove deletados.
# Em caso de conflito, exibe detalhes claros no terminal e aborta.

set -euo pipefail

# =============================
# Cores para output no terminal
# =============================

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}ℹ️  $*${RESET}"; }
success() { echo -e "${GREEN}${BOLD}✅ $*${RESET}"; }
warn()    { echo -e "${YELLOW}${BOLD}⚠️  $*${RESET}"; }
error()   { echo -e "${RED}${BOLD}❌ $*${RESET}"; }

# =============================
# Exibe conflitos de forma clara
# Lista cada arquivo em conflito com o tipo de conflito
# =============================

show_conflicts() {
    error "=========================================="
    error "  CONFLITO DETECTADO — sync abortado"
    error "=========================================="
    echo ""

    # Lista os arquivos em conflito com o status do git
    CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null)

    if [ -n "$CONFLICTS" ]; then
        echo -e "${RED}${BOLD}Arquivos em conflito:${RESET}"
        while IFS= read -r file; do
            echo -e "  ${RED}• $file${RESET}"
            # Mostra os marcadores de conflito encontrados no arquivo
            if grep -q "<<<<<<" "$file" 2>/dev/null; then
                echo -e "    ${YELLOW}→ Contém marcadores <<<<<<< / ======= / >>>>>>>${RESET}"
            fi
        done <<< "$CONFLICTS"
    fi

    echo ""
    echo -e "${BOLD}Como resolver:${RESET}"
    echo -e "  1. Edite cada arquivo acima e resolva os conflitos manualmente"
    echo -e "  2. Marque como resolvido:  ${CYAN}git add <arquivo>${RESET}"
    echo -e "  3. Conclua o rebase:       ${CYAN}git rebase --continue${RESET}"
    echo -e "     (ou cancele:            ${CYAN}git rebase --abort${RESET})"
    echo -e "  4. Execute novamente:      ${CYAN}./sync.git.sh${RESET}"
    echo ""
}

# =============================
# Validação do repositório
# Usa o .git DA pasta Emulador/ (raiz é sempre a pasta pai deste script),
# ignorando qualquer repo Git "wrapper" acima.
# =============================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ ! -d "$REPO_ROOT/.git" ]; then
    error "Não há repositório Git em $REPO_ROOT"
    echo -e "  Execute primeiro: ${CYAN}./Exec_Git/init.git.sh${RESET}"
    exit 1
fi

# Força o git a usar este .git, mesmo se houver um repo Git acima
export GIT_DIR="$REPO_ROOT/.git"
export GIT_WORK_TREE="$REPO_ROOT"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"

echo ""
info "Repo  : $REPO_ROOT"
info "Branch: $BRANCH"
echo ""

# =============================
# Verifica se há um rebase em andamento
# (pode ter sido deixado de uma execução anterior)
# =============================

if [ -d "$REPO_ROOT/.git/rebase-merge" ] || [ -d "$REPO_ROOT/.git/rebase-apply" ]; then
    error "Há um rebase em andamento. Resolva antes de continuar:"
    echo -e "  Continuar : ${CYAN}git rebase --continue${RESET}"
    echo -e "  Cancelar  : ${CYAN}git rebase --abort${RESET}"
    exit 1
fi

# =============================
# Stash das alterações locais
# (necessário para fazer pull --rebase sem conflitos de working tree)
# =============================

STASHED=0
HAS_UNTRACKED=$(git ls-files --others --exclude-standard | wc -l)

if ! git diff --quiet || ! git diff --cached --quiet || [ "$HAS_UNTRACKED" -gt 0 ]; then
    warn "Alterações locais detectadas — guardando temporariamente (stash)..."
    git stash push --include-untracked -m "sync.git.sh auto-stash $(date '+%Y-%m-%d %H:%M:%S')"
    STASHED=1
fi

# =============================
# Pull com rebase do remoto
# Garante histórico linear sem merge commits
# =============================

info "Buscando atualizações do remoto..."

if ! git pull --rebase origin "$BRANCH" 2>&1; then
    # Pull falhou — pode ser conflito ou problema de rede
    if [ -d "$REPO_ROOT/.git/rebase-merge" ] || [ -d "$REPO_ROOT/.git/rebase-apply" ]; then
        show_conflicts
    else
        error "Falha ao conectar ao remoto. Verifique a conexão e as credenciais."
    fi
    # Restaura o stash antes de sair para não perder trabalho local
    if [ "$STASHED" = "1" ]; then
        warn "Restaurando stash local antes de sair..."
        git stash pop || warn "Stash não pôde ser restaurado. Use: git stash pop"
    fi
    exit 1
fi

# =============================
# Restaura alterações locais
# =============================

if [ "$STASHED" = "1" ]; then
    info "Restaurando alterações locais..."
    if ! git stash pop; then
        echo ""
        error "=========================================="
        error "  CONFLITO AO RESTAURAR STASH"
        error "=========================================="
        echo ""
        warn "Suas alterações locais entram em conflito com as mudanças do remoto."
        echo ""
        STASH_CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null)
        if [ -n "$STASH_CONFLICTS" ]; then
            echo -e "${RED}${BOLD}Arquivos em conflito:${RESET}"
            while IFS= read -r file; do
                echo -e "  ${RED}• $file${RESET}"
            done <<< "$STASH_CONFLICTS"
        fi
        echo ""
        echo -e "${BOLD}Como resolver:${RESET}"
        echo -e "  1. Edite os arquivos acima e resolva os marcadores de conflito"
        echo -e "  2. ${CYAN}git add <arquivo>${RESET}"
        echo -e "  3. ${CYAN}./sync.git.sh${RESET}  (o stash já foi aplicado parcialmente)"
        echo ""
        exit 1
    fi
fi

# =============================
# Adiciona todas as alterações:
# - arquivos novos (incluindo gerados localmente)
# - modificações
# - deleções (arquivos removidos do disco)
# =============================

info "Preparando arquivos para commit..."

# Mostra resumo do que será incluído
ADDED=$(git diff --cached --name-only --diff-filter=A | wc -l)
MODIFIED=$(git diff --name-only | wc -l)
DELETED=$(git ls-files --deleted | wc -l)
UNTRACKED=$(git ls-files --others --exclude-standard | wc -l)

git add -A   # adiciona tudo: novos, modificados e remove deletados do índice

# Exibe resumo das mudanças staged
if ! git diff --cached --quiet; then
    echo ""
    echo -e "${BOLD}Mudanças a commitar:${RESET}"
    git diff --cached --stat | sed 's/^/  /'
    echo ""
fi

# =============================
# Commit
# =============================

if git diff --cached --quiet; then
    warn "Nenhuma mudança para commitar. Repositório já está atualizado."
else
    COMMIT_MSG="sync: $(date '+%Y-%m-%d %H:%M:%S')"
    info "Commitando: $COMMIT_MSG"
    git commit -m "$COMMIT_MSG"
fi

# =============================
# Push para o GitHub
# =============================

info "Enviando para o GitHub (branch: $BRANCH)..."

if ! git push origin "$BRANCH" 2>&1; then
    error "Falha no push. O remoto pode ter commits mais novos."
    echo -e "  Tente executar ${CYAN}./sync.git.sh${RESET} novamente."
    exit 1
fi

echo ""
success "Sync concluído com sucesso!"
echo ""
