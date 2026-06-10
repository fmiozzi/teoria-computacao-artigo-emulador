#!/usr/bin/env bash
# Roda o monitor sobre todos os traços de Files/Traces/ (ou diretório dado).
set -uo pipefail

DIR="${1:-Files/Traces}"

if [ ! -d "$DIR" ]; then
  echo "Diretório não encontrado: $DIR"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

shopt -s nullglob
TRACES=("$DIR"/*.txt)
shopt -u nullglob

if [ "${#TRACES[@]}" -eq 0 ]; then
  echo "Nenhum traço encontrado em $DIR"
  exit 0
fi

echo "Processando ${#TRACES[@]} traço(s) em: $DIR"
echo "=========================================="

# Contagem por decisão do gate (§5.4), via código de saída do CLI:
#   0 = LIBERAR (liberado_integracao); 2 = BLOQUEAR (divergencia_pcp |
#   erro_classificacao | erro_decisao); 3 = pendente; demais = erro.
LIBERADAS=0
BLOQUEADAS=0
PENDENTES=0
ERROS=0

for trace in "${TRACES[@]}"; do
  set +e
  "$SCRIPT_DIR/monitor.sh" --quiet "$trace"
  rc=$?
  set -e

  case "$rc" in
    0) LIBERADAS=$((LIBERADAS + 1)) ;;
    2) BLOQUEADAS=$((BLOQUEADAS + 1)) ;;
    3) PENDENTES=$((PENDENTES + 1)) ;;
    *) ERROS=$((ERROS + 1)) ;;
  esac
done

echo ""
echo "=========================================="
echo "Liberadas (LIBERAR) : $LIBERADAS"
echo "Bloqueadas (BLOQUEAR): $BLOQUEADAS"
if [ "$PENDENTES" -gt 0 ]; then
  echo "Pendentes           : $PENDENTES"
fi
if [ "$ERROS" -gt 0 ]; then
  echo "Erros               : $ERROS"
fi
