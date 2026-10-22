#!/usr/bin/env bash
set -e

echo "================================================================"
echo "  ARBORIA ENGINE — EXECUCAO DA BATERIA DE BENCHMARK REAL"
echo "================================================================"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if command -v python3 >/dev/null 2>&1; then
    python3 bench/runner.py
elif command -v python >/dev/null 2>&1; then
    python bench/runner.py
else
    echo "[ERRO] Python nao encontrado no PATH!"
    exit 1
fi

echo "================================================================"
echo "  BENCHMARK EXECUTADO COM SUCESSO!"
echo "================================================================"
exit 0
