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
import shutil
import glob

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "project"))
REPO_ROOT = os.path.normpath(os.path.join(SCRIPT_DIR, ".."))

def find_godot_bin():
    if "GODOT_BIN" in os.environ and os.path.isfile(os.environ["GODOT_BIN"]):
        return os.environ["GODOT_BIN"]
    
    localapp = os.environ.get("LOCALAPPDATA", "")
    import glob
    candidates = [
        os.path.join(REPO_ROOT, "bin", "godot_console.exe"),
        os.path.join(REPO_ROOT, "bin", "godot.exe"),
        shutil.which("godot"),
        shutil.which("godot4"),
        shutil.which("godot_console.exe"),
    ]
    if localapp:
        winget_pattern = os.path.join(localapp, "Microsoft", "WinGet", "Packages", "GodotEngine.GodotEngine*", "*console.exe")
        candidates.extend(glob.glob(winget_pattern))
        winget_pattern_gui = os.path.join(localapp, "Microsoft", "WinGet", "Packages", "GodotEngine.GodotEngine*", "Godot*.exe")
        candidates.extend(glob.glob(winget_pattern_gui))

    for c in candidates:
        if c and os.path.isfile(c):
            return os.path.normpath(c)
    raise RuntimeError("Executavel do Godot nao encontrado. Defina GODOT_BIN.")

def ensure_dependencies(godot_bin):
    """Garante que as dependências necessárias para a cena de benchmark existam em um clone limpo."""
    vg_target = os.path.join(PROJECT_DIR, "assets", "dense_rock_test.vgmesh")
    obj_source = os.path.join(REPO_ROOT, "assets", "dense_rock_test.obj")
    baker_bin = os.path.join(REPO_ROOT, "baker", "build", "arboria_baker_cli.exe")
    
    # Se o .vgmesh não existir, tenta compilar ou rodar o baker
    if not os.path.isfile(vg_target) and os.path.isfile(obj_source) and os.path.isfile(baker_bin):
        print("[INIT] Gerando dense_rock_test.vgmesh via baker...")
        os.makedirs(os.path.dirname(vg_target), exist_ok=True)
        subprocess.run([baker_bin, obj_source, vg_target, "--verify"], check=True)
        # Sincroniza também para assets/
        shutil.copyfile(vg_target, os.path.join(REPO_ROOT, "assets", "dense_rock_test.vgmesh"))

    # Se o cache de scripts do Godot não existir, força indexação inicial
    class_cache = os.path.join(PROJECT_DIR, ".godot", "global_script_class_cache.cfg")
    if not os.path.isfile(class_cache):
        print("[INIT] Gerando cache de classes do Godot (.godot/global_script_class_cache.cfg)...")
        try:
            subprocess.run([godot_bin, "--headless", "--editor", "--quit", "--path", PROJECT_DIR],
                           timeout=30, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            print(f"[WARN] Indexacao do Godot retornou: {e}")

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
    ensure_dependencies(godot_bin)
    
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
