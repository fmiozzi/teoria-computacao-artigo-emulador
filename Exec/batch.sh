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

ACEITAS=0
VIOLAS=0
ERROS=0

for trace in "${TRACES[@]}"; do
  set +e
  "$SCRIPT_DIR/monitor.sh" --quiet "$trace"
  rc=$?
  set -e

  case "$rc" in
    0) ACEITAS=$((ACEITAS + 1)) ;;
    2) VIOLAS=$((VIOLAS + 1)) ;;
    *) ERROS=$((ERROS + 1)) ;;
  esac
done

echo ""
echo "=========================================="
echo "Aceitas : $ACEITAS"
echo "Violadas: $VIOLAS"
if [ "$ERROS" -gt 0 ]; then
  echo "Erros   : $ERROS"
fi
