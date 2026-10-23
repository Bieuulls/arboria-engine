#!/usr/bin/env python3
"""
ARBORIA ENGINE — BENCHMARK RIGOROSO: JOLT PHYSICS VS GODOTPHYSICS3D
Executa bateria de testes comparativos em hardware real (RTX 3050).
Compara 100, 500 e 1.000 corpos a 60 Hz e 120 Hz com 3 execuções por cenário.
"""

import sys
import os
import json
import subprocess
import re
from pathlib import Path

GODOT_BIN = r"C:\Users\srgab\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
PROJECT_DIR = Path(r"D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL\project")
PROJECT_FILE = PROJECT_DIR / "project.godot"
ARTIFACTS_DIR = Path(r"D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL\artifacts")

def set_physics_engine(engine_name: str):
    text = PROJECT_FILE.read_text(encoding="utf-8")
    if "3d/physics_engine" in text:
        text = re.sub(r'3d/physics_engine="[^"]*"', f'3d/physics_engine="{engine_name}"', text)
    else:
        text += f'\n[physics]\n\n3d/physics_engine="{engine_name}"\n'
    PROJECT_FILE.write_text(text, encoding="utf-8")

def run_single_benchmark(bodies: int, ticks: int, duration_frames: int = 180) -> dict:
    cmd = [
        GODOT_BIN,
        "--headless",
        "--path", str(PROJECT_DIR),
        "scenes/benchmark_physics_runner.tscn",
        "--",
        f"--bodies={bodies}",
        f"--ticks={ticks}",
        f"--duration={duration_frames}"
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    for line in proc.stdout.splitlines():
        if "[BENCHMARK_PHYSICS_DATA]" in line:
            json_str = line.split("[BENCHMARK_PHYSICS_DATA]")[1].strip()
            return json.loads(json_str)
    raise RuntimeError(f"Falha ao coletar dados do benchmark. Exit: {proc.returncode}\nStderr: {proc.stderr[:300]}")

def average_metrics(runs: list[dict]) -> dict:
    if not runs:
        return {}
    avg = dict(runs[0])
    keys_to_avg = [
        "physics_step_ms_p50", "physics_step_ms_p95", "physics_step_ms_p99",
        "frame_time_ms_p95", "active_rigid_bodies", "sleeping_bodies",
        "collision_contacts", "memory_mb"
    ]
    for k in keys_to_avg:
        vals = [r[k] for r in runs if k in r]
        avg[k] = round(sum(vals) / len(vals), 3)
    return avg

def main():
    print("==========================================================================")
    print(" INICIANDO BATERIA DE BENCHMARK FÍSICO: JOLT PHYSICS VS GODOTPHYSICS3D   ")
    print(" Hardware: NVIDIA GeForce RTX 3050 | Godot 4.7.2 Forward+ Vulkan          ")
    print(" Cenários: 100, 500 e 1.000 Corpos | Frequências: 60 Hz e 120 Hz         ")
    print(" Repetições: 3 execuções por cenário para eliminação de ruído estatístico")
    print("==========================================================================")

    scenarios = [
        {"bodies": 100, "ticks": 60},
        {"bodies": 500, "ticks": 60},
        {"bodies": 1000, "ticks": 60},
        {"bodies": 100, "ticks": 120},
        {"bodies": 500, "ticks": 120},
        {"bodies": 1000, "ticks": 120},
    ]

    results = {
        "godot_physics": {},
        "jolt_physics": {},
        "comparison": []
    }

    original_content = PROJECT_FILE.read_text(encoding="utf-8")

    try:
        # 1. BATERIA BASELINE: GodotPhysics3D (DEFAULT)
        print("\n>>> EXECUTANDO BASELINE: GodotPhysics3D (DEFAULT)...")
        set_physics_engine("DEFAULT")
        for sc in scenarios:
            b, t = sc["bodies"], sc["ticks"]
            key = f"{b}_bodies_{t}hz"
            print(f"  -> Rodando GodotPhysics3D: {b} corpos @ {t} Hz (3 execuções)...", end="", flush=True)
            runs = []
            for r in range(3):
                data = run_single_benchmark(b, t)
                runs.append(data)
                print(".", end="", flush=True)
            avg = average_metrics(runs)
            results["godot_physics"][key] = avg
            print(f" Concluído! Step p95: {avg['physics_step_ms_p95']:.3f} ms | Mem: {avg['memory_mb']:.1f} MB")

        # 2. BATERIA CANDIDATO: Jolt Physics
        print("\n>>> EXECUTANDO CANDIDATO: Jolt Physics...")
        set_physics_engine("Jolt Physics")
        for sc in scenarios:
            b, t = sc["bodies"], sc["ticks"]
            key = f"{b}_bodies_{t}hz"
            print(f"  -> Rodando Jolt Physics: {b} corpos @ {t} Hz (3 execuções)...", end="", flush=True)
            runs = []
            for r in range(3):
                data = run_single_benchmark(b, t)
                runs.append(data)
                print(".", end="", flush=True)
            avg = average_metrics(runs)
            results["jolt_physics"][key] = avg
            print(f" Concluído! Step p95: {avg['physics_step_ms_p95']:.3f} ms | Mem: {avg['memory_mb']:.1f} MB")

    finally:
        # Restaura a configuração do projeto com Jolt Physics ativo
        set_physics_engine("Jolt Physics")

    # 3. COMPARAÇÃO E ANÁLISE RELATIVA
    print("\n==========================================================================")
    print(" TABELA COMPARATIVA DEFINITIVA: JOLT PHYSICS VS GODOTPHYSICS3D            ")
    print("==========================================================================")
    print(f"{'Cenário':<18} | {'GodotPhys p95':<14} | {'Jolt p95':<12} | {'Ganho p95 (%)':<14} | {'Godot Mem':<10} | {'Jolt Mem':<10}")
    print("-" * 88)

    for sc in scenarios:
        b, t = sc["bodies"], sc["ticks"]
        key = f"{b}_bodies_{t}hz"
        gp = results["godot_physics"][key]
        jp = results["jolt_physics"][key]

        gp_p95 = gp["physics_step_ms_p95"]
        jp_p95 = jp["physics_step_ms_p95"]
        
        # Ganho percentual no tempo de step físico (redução de tempo = ganho positivo)
        gain_pct = ((gp_p95 - jp_p95) / gp_p95) * 100.0 if gp_p95 > 0 else 0.0

        comp_entry = {
            "scenario": key,
            "bodies": b,
            "ticks_hz": t,
            "godot_physics_step_p95_ms": gp_p95,
            "jolt_physics_step_p95_ms": jp_p95,
            "speedup_gain_pct": round(gain_pct, 2),
            "godot_physics_mem_mb": gp["memory_mb"],
            "jolt_physics_mem_mb": jp["memory_mb"]
        }
        results["comparison"].append(comp_entry)

        print(f"{key:<18} | {gp_p95:<14.3f} | {jp_p95:<12.3f} | {gain_pct:+13.2f}% | {gp['memory_mb']:<7.1f} MB | {jp['memory_mb']:<7.1f} MB")

    print("==========================================================================")

    # Salva relatório em artifacts
    ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)
    report_file = ARTIFACTS_DIR / "benchmark_jolt_vs_godotphysics.json"
    report_file.write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(f"\n[RELATÓRIO CONCLUÍDO] Salvo com sucesso em: {report_file}")

if __name__ == "__main__":
    main()
