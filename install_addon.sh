#!/usr/bin/env bash
set -e

echo "===================================================================="
echo "  ARBORIA VIRTUAL GEOMETRY - GODOT 4 ADDON INSTALLER"
echo "===================================================================="

TARGET_DIR="$1"

if [ -z "$TARGET_DIR" ]; then
    echo ""
    echo "[ERRO] Nenhum diretorio de destino informado."
    echo "Uso: ./install_addon.sh <caminho_do_seu_projeto_godot>"
    echo "Exemplo: ./install_addon.sh /home/user/meu_projeto_godot"
    exit 1
fi

if [ ! -f "$TARGET_DIR/project.godot" ]; then
    echo "[AVISO] 'project.godot' nao encontrado em '$TARGET_DIR'."
    read -p "Deseja continuar mesmo assim? (y/N): " confirm
    if [[ "$confirm" != [yY] && "$confirm" != [yY][eE][sS] ]]; then
        echo "Instalacao cancelada."
        exit 1
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ADDON="$SCRIPT_DIR/addons/arboria"
DEST_ADDON="$TARGET_DIR/addons/arboria"

echo "[1/3] Copiando arquivos do plugin para '$DEST_ADDON'..."
mkdir -p "$DEST_ADDON"
cp -r "$SOURCE_ADDON/"* "$DEST_ADDON/"

echo "[2/3] Verificando binarios compilados..."
if [ -f "$SCRIPT_DIR/bin/libarboria_native.so" ]; then
    mkdir -p "$DEST_ADDON/bin"
    cp "$SCRIPT_DIR/bin/libarboria_native.so" "$DEST_ADDON/bin/"
    echo "  - Binario Linux copiado para addons/arboria/bin/"
fi

echo "[3/3] Concluindo instalacao..."
echo ""
echo "===================================================================="
echo "[SUCESSO] ARBORIA instalado com sucesso!"
echo "Ative em: Project Settings -> Plugins -> Arboria Virtual Geometry"
echo "===================================================================="
