#!/usr/bin/env bash
set -e

echo "================================================================"
echo "  ARBORIA ENGINE — SISTEMA DE BUILD REPRODUZIVEL (Linux/macOS)"
echo "================================================================"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

command -v cmake >/dev/null 2>&1 || { echo "[ERRO] CMake nao encontrado no PATH!"; exit 1; }

echo "[1/4] Compilando ARBORIA Baker (tools/baker)..."
cmake -B tools/baker/build -S tools/baker -DCMAKE_BUILD_TYPE=Release
cmake --build tools/baker/build --config Release -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

echo "[2/4] Compilando ARBORIA Native Core e GDExtension (native/renderer)..."
cmake -B native/renderer/build -S native/renderer -DCMAKE_BUILD_TYPE=Release
cmake --build native/renderer/build --config Release -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

echo "[3/4] Executando Testes Unitarios C++ (CTest)..."
ctest --test-dir native/renderer/build --output-on-failure

echo "[4/4] Verificando Artefatos Gerados..."
if [ ! -f "bin/vg_baker_cli" ] && [ ! -f "bin/vg_baker_cli.exe" ]; then
    echo "[ERRO] Executavel do Baker nao foi gerado!"
    exit 1
fi

echo "================================================================"
echo "  BUILD CONCLUIDO COM SUCESSO E REPRODUZIVEL!"
echo "================================================================"
exit 0
