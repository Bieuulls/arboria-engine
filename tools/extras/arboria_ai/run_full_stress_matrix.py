"""
ARBORIA ENGINE - MATRIZ DE TESTES E BENCHMARK DE ESTRESSE GPU/VULKAN
Executa os 4 cenários obrigatórios (1, 80, 500, 2000 instâncias)
com 3 malhas distintas no mesmo lote global, medindo tempos reais na RTX 3050.
"""

import sys
import subprocess
import json
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
GODOT_BIN = r"D:\ARBORIA_ENGINE\bin\godot_console.exe"
PROJECT_DIR = REPO_ROOT / "project"
OUTPUT_REPORT = REPO_ROOT / "artifacts" / "gpu_stress_matrix_report.json"

SCENARIOS = [1, 80, 500, 2000]

def run_scenario(instances: int, bench_frames: int = 1300):
    cmd = [
        GODOT_BIN,
        "--rendering-driver", "vulkan",
        "--path", str(PROJECT_DIR),
        "scenes/arboria_massive_world_demo.tscn",
        f"--instances={instances}",
        f"--bench-frames={bench_frames}",
        f"--capture-path=res://diag_bench_{instances}.png"
    ]
    print(f"\n[STRESS RUN] Executando cenário com {instances} instâncias ({bench_frames} frames)...")
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180, encoding="utf-8", errors="replace")
    
    stdout = proc.stdout
    if proc.returncode != 0:
        print(f"[ERRO] Cenário {instances} falhou (exit {proc.returncode}):\n{proc.stderr}\n{stdout}", file=sys.stderr)
        return None

    # Parse metrics from stdout
    result = {
        "instances": instances,
        "clusters_visible": 0,
        "triangles_drawn": 0,
        "clusters_evaluated": 0,
        "frame_time_p50_ms": 0.0,
        "frame_time_p95_ms": 0.0,
        "frame_time_p99_ms": 0.0,
        "cpu_submission_avg_ms": 0.0,
        "dispatches": 0,
        "draw_calls": 0,
        "vram_resident_mb": 0.0
    }

    for line in stdout.splitlines():
        if "Clusters Visíveis:" in line:
            m = re.search(r"Clusters Visíveis:\s*(\d+)", line)
            if m: result["clusters_visible"] = int(m.group(1))
        elif "Triângulos Desenhados:" in line:
            m = re.search(r"Triângulos Desenhados:\s*(\d+)", line)
            if m: result["triangles_drawn"] = int(m.group(1))
        elif "Clusters Avaliados:" in line:
            m = re.search(r"Clusters Avaliados:\s*(\d+)", line)
            if m: result["clusters_evaluated"] = int(m.group(1))
        elif "Frame Time p50:" in line:
            m = re.search(r"p50:\s*([\d\.]+)\s*ms\s*\|\s*p95:\s*([\d\.]+)\s*ms\s*\|\s*p99:\s*([\d\.]+)", line)
            if m:
                result["frame_time_p50_ms"] = float(m.group(1))
                result["frame_time_p95_ms"] = float(m.group(2))
                result["frame_time_p99_ms"] = float(m.group(3))
        elif "Custo CPU Submissão Médio:" in line:
            m = re.search(r"Médio:\s*([\d\.]+)\s*ms", line)
            if m: result["cpu_submission_avg_ms"] = float(m.group(1))
        elif "Dispatches:" in line:
            m = re.search(r"Dispatches:\s*(\d+)\s*\|\s*Draw Calls:\s*(\d+)", line)
            if m:
                result["dispatches"] = int(m.group(1))
                result["draw_calls"] = int(m.group(2))
        elif "VRAM Residente Estimada:" in line:
            m = re.search(r"Estimada:\s*([\d\.]+)\s*MB", line)
            if m: result["vram_resident_mb"] = float(m.group(1))

    print(f"  -> Concluído: {result['clusters_visible']} clusters visíveis, {result['triangles_drawn']} triângulos, Frame p95: {result['frame_time_p95_ms']} ms, CPU submit: {result['cpu_submission_avg_ms']} ms")
    return result

def main():
    OUTPUT_REPORT.parent.mkdir(parents=True, exist_ok=True)
    all_results = []
    
    # Executa cenários com warmup e medição
    for count in SCENARIOS:
        res = run_scenario(count, bench_frames=450) # 300 warmup + 150 medidos em movimento contínuo
        if res:
            all_results.append(res)
    
    OUTPUT_REPORT.write_text(json.dumps(all_results, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\n[SUCESSO] Relatório da matriz de estresse gravado em {OUTPUT_REPORT}")

if __name__ == "__main__":
    main()
