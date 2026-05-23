#!/usr/bin/env bash
# Executa o monitor LTL sobre um arquivo de traço.
# Aceita as mesmas flags do executável: --quiet | --json.
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Uso: $0 [--quiet|--json] <arquivo_de_traço>"
  echo ""
  echo "Exemplos:"
  echo "  $0 Files/Traces/trace_01_aceita_simples.txt          # formato detalhado"
  echo "  $0 --quiet Files/Traces/trace_01_aceita_simples.txt  # formato curto"
  echo "  $0 --json  Files/Traces/trace_01_aceita_simples.txt  # JSON"
  exit 1
fi

# Localiza a raiz do projeto a partir da posição deste script.
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Se houver flake.nix no projeto, usa nix develop; caso contrário, cabal direto.
if command -v nix >/dev/null 2>&1 && [ -f flake.nix ]; then
  nix develop --command cabal run -v0 lab-monitor -- "$@"
else
  cabal run -v0 lab-monitor -- "$@"
fi
