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

echo "[1.5/4] Gerando malhas virtuais de referencia (.vgmesh) via Baker..."
mkdir -p assets project/assets
BAKER_BIN="bin/arboria_baker_cli"
[ ! -f "$BAKER_BIN" ] && BAKER_BIN="bin/arboria_baker_cli.exe"
[ ! -f "$BAKER_BIN" ] && BAKER_BIN="bin/vg_baker_cli"
[ ! -f "$BAKER_BIN" ] && BAKER_BIN="bin/vg_baker_cli.exe"

if [ -f "$BAKER_BIN" ]; then
    if [ -f "assets/dense_rock_test.obj" ]; then
        "$BAKER_BIN" assets/dense_rock_test.obj assets/dense_rock.vgmesh
        cp assets/dense_rock.vgmesh assets/dense_rock_verified.vgmesh
        cp assets/dense_rock.vgmesh project/assets/dense_rock.vgmesh
        cp assets/dense_rock.vgmesh project/assets/dense_rock_test.vgmesh
        cp assets/dense_rock.vgmesh project/assets/dense_rock_verified.vgmesh
    fi
    if [ -f "assets/boulder_granite.obj" ]; then
        "$BAKER_BIN" assets/boulder_granite.obj assets/boulder_granite.vgmesh
        cp assets/boulder_granite.vgmesh project/assets/boulder_granite.vgmesh
    fi
    if [ -f "assets/pine_trunk_complex.obj" ]; then
        "$BAKER_BIN" assets/pine_trunk_complex.obj assets/pine_trunk_complex.vgmesh
        cp assets/pine_trunk_complex.vgmesh project/assets/pine_trunk_complex.vgmesh
    fi
    if [ -f "assets/small_mesh_test.obj" ]; then
        "$BAKER_BIN" assets/small_mesh_test.obj assets/small_mesh.vgmesh
        cp assets/small_mesh.vgmesh project/assets/small_mesh.vgmesh
    fi
    if [ -f "assets/rock_cluster.obj" ]; then
        "$BAKER_BIN" assets/rock_cluster.obj project/assets/rock_cluster_baked.vgmesh
    fi
fi

echo "[2/4] Compilando ARBORIA Native Core e GDExtension (native/renderer)..."
cmake -B native/renderer/build -S native/renderer -DCMAKE_BUILD_TYPE=Release
cmake --build native/renderer/build --config Release -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

echo "[3/4] Executando Testes Unitarios C++ (CTest)..."
ctest --test-dir native/renderer/build --output-on-failure

echo "[4/4] Verificando Artefatos Gerados..."
if [ ! -f "bin/arboria_baker_cli" ] && [ ! -f "bin/arboria_baker_cli.exe" ] && [ ! -f "bin/vg_baker_cli" ] && [ ! -f "bin/vg_baker_cli.exe" ]; then
    echo "[ERRO] Executavel do Baker nao foi gerado!"
    exit 1
fi

mkdir -p addons/arboria/bin
if [ -f "project/bin/libarboria_native.so" ]; then
    cp project/bin/libarboria_native.so addons/arboria/bin/
elif [ -f "project/bin/libarboria_native.dylib" ]; then
    cp project/bin/libarboria_native.dylib addons/arboria/bin/
elif [ -f "project/bin/libarboria_native.dll" ]; then
    cp project/bin/libarboria_native.dll addons/arboria/bin/
fi

echo "[Extra 0] Sincronizando canonical addons/arboria para project/addons/arboria..."
mkdir -p project/addons/arboria
cp -r addons/arboria/* project/addons/arboria/ 2>/dev/null || true

echo "[Extra] Sincronizando assets/ com project/assets/ para o Godot..."
mkdir -p project/assets
cp -u assets/*.vgmesh project/assets/ 2>/dev/null || true
cp -u assets/*.obj project/assets/ 2>/dev/null || true

echo "[Extra 2] Indexando projeto e classes do Godot (.godot cache)..."
GODOT_EXE="${GODOT_BIN:-}"
[ -z "$GODOT_EXE" ] && command -v godot >/dev/null 2>&1 && GODOT_EXE="godot"
[ -z "$GODOT_EXE" ] && command -v godot4 >/dev/null 2>&1 && GODOT_EXE="godot4"
if [ -n "$GODOT_EXE" ]; then
    "$GODOT_EXE" --headless --editor --quit --path project >/dev/null 2>&1 || true
fi

echo "================================================================"
echo "  BUILD CONCLUIDO COM SUCESSO E REPRODUZIVEL!"
echo "================================================================"
exit 0
