#!/usr/bin/env python3
"""
ARBORIA ENGINE - TESTE AUTOMATIZADO DE PARIDADE DE PRIMITIVAS LOD0 (ETAPA 2)
Verifica que, com LOD0 forçado, as primitivas renderizadas pelo ARBORIA
são idênticas às primitivas de referência do Godot (diferença = 0)
para 1, 80 e 500 instâncias de dense_rock (15.800 triângulos cada).
"""

import os
import sys
import json
import subprocess
import re

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "project"))
REPO_ROOT = os.path.normpath(os.path.join(SCRIPT_DIR, ".."))

def find_godot_bin():
    if "GODOT_BIN" in os.environ and os.path.isfile(os.environ["GODOT_BIN"]):
        return os.environ["GODOT_BIN"]
    default_path = r"C:\Users\srgab\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
    if os.path.isfile(default_path):
        return default_path
    import shutil
    cand = shutil.which("godot") or shutil.which("godot4")
    if cand:
        return cand
    raise RuntimeError("Executavel do Godot nao encontrado. Defina GODOT_BIN.")

def run_arboria_lod0(godot_bin, instance_count):
    cmd = [
        godot_bin,
        "--path", PROJECT_DIR,
        "--scene", "res://bench/benchmark_scene.tscn",
        "--",
        "--scenario", "dense_rock",
        "--variant", "arboria_lod0",
        "--instances", str(instance_count),
        "--mesh-vg", "res://assets/dense_rock_test.vgmesh",
        "--mesh-obj", "res://assets/dense_rock_test.obj",
        "--warmup", "5",
        "--measured", "5"
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120)
    stdout = proc.stdout
    
    # Extrai primitivas da saída do benchmark
    # Exemplo: "   Draw Calls / Primitives  : 1 / 1264000" ou "ARBORIA Triangulos Reais : 1264000"
    m_prims = re.search(r"ARBORIA Triangulos Reais\s*:\s*(\d+)", stdout)
    if not m_prims:
        m_prims = re.search(r"Primitives\s*:\s*\d+\s*/\s*(\d+)", stdout)
    
    if not m_prims:
        raise RuntimeError(f"Nao foi possivel extrair contagem de primitivas. Retorno Godot: {proc.returncode}\nSaida:\n{stdout}")
    
    prims = int(m_prims.group(1))
    return prims, stdout

def main():
    print("=" * 70)
    print(" ARBORIA ENGINE - TESTE AUTOMATICO DE PARIDADE DE PRIMITIVAS LOD0")
    print("=" * 70)
    
    godot_bin = find_godot_bin()
    print(f"Godot Binario: {godot_bin}")
    print(f"Projeto      : {PROJECT_DIR}\n")
    
    TRIANGLES_PER_INSTANCE = 15800
    test_cases = [1, 80, 500]
    results = []
    all_passed = True
    
    for count in test_cases:
        expected_godot = count * TRIANGLES_PER_INSTANCE
        print(f"--- Testando {count} instancia(s) ---")
        print(f"  Primitivas esperadas Godot (LOD0) : {expected_godot}")
        
        arboria_prims, stdout = run_arboria_lod0(godot_bin, count)
        diff = abs(arboria_prims - expected_godot)
        passed = (diff == 0)
        
        print(f"  Primitivas medidas ARBORIA LOD0   : {arboria_prims}")
        print(f"  Diferenca (ARBORIA - Godot)       : {diff}")
        print(f"  Status                            : {'PASSOU' if passed else 'FALHOU'}\n")
        
        results.append({
            "instances": count,
            "godot_primitives": expected_godot,
            "arboria_primitives": arboria_prims,
            "difference": diff,
            "passed": passed
        })
        
        if not passed:
            all_passed = False
            
    print("=" * 70)
    print(" RESUMO DA VALIDACAO DE PARIDADE DE PRIMITIVAS")
    print("=" * 70)
    for r in results:
        status_str = "PASSOU (Diferenca = 0)" if r["passed"] else f"FALHOU (Diferenca = {r['difference']})"
        print(f"  - {r['instances']} instancias: Godot={r['godot_primitives']} | ARBORIA={r['arboria_primitives']} -> {status_str}")
        
    print("=" * 70)
    if all_passed:
        print(" CRITERIO ATENDIDO: diferenca de primitivas LOD0 = 0 nas tres contagens.")
        print(" RESULTADO FINAL: PASSOU")
        sys.exit(0)
    else:
        print(" CRITERIO NAO ATENDIDO.")
        print(" RESULTADO FINAL: FALHOU")
        sys.exit(1)

if __name__ == "__main__":
    main()
