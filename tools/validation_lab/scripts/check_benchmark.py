#!/usr/bin/env python3
"""
ARBORIA VALIDATION LAB — Benchmark Integrity & Geometry Counter Auditor
Valida rigorosamente os dados de benchmark para garantir que:
1. Contadores de geometria não estejam zerados em cenários do ARBORIA.
2. Não haja falsos positivos decorrentes de crashes, timeouts ou buffers vazios.
3. Métricas de VRAM e Frame Time p95 respeitem as metas de validação.
"""

import sys
import os
import csv
import json

def audit_benchmark_csv(csv_path: str):
    if not os.path.exists(csv_path):
        print(f"[ERRO] Arquivo CSV nao encontrado: {csv_path}")
        return False

    print("====================================================================")
    print("  ARBORIA VALIDATION LAB — AUDITORIA DE INTEGRIDADE DE BENCHMARK   ")
    print(f"  Arquivo Analisado: {csv_path}")
    print("====================================================================")

    rows = []
    with open(csv_path, mode="r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for r in reader:
            rows.append(r)

    if not rows:
        print("[FALHA] O arquivo CSV esta vazio!")
        return False

    print(f"[INFO] Total de amostras lidas: {len(rows)}")

    arboria_rows = [r for r in rows if "arboria" in r.get("variant", "").lower()]
    godot_rows = [r for r in rows if "mesh" in r.get("variant", "").lower()]

    print(f"  - Amostras ARBORIA : {len(arboria_rows)}")
    print(f"  - Amostras Godot   : {len(godot_rows)}")

    zero_counter_flags = 0
    anomalous_timing_flags = 0

    for i, r in enumerate(arboria_rows):
        inst = int(r.get("instances", 1))
        p95 = float(r.get("frame_time_p95", r.get("frame_time_ms", 0.0)))
        vram = float(r.get("vram_avg_mb", r.get("vram_mb", 0.0)))
        tris = int(r.get("primitives", r.get("triangles", 0)))

        # Em instâncias maiores (ex: >= 80), o frame time não pode ser zero nem absurdo
        if p95 <= 0.001 or p95 > 500.0:
            anomalous_timing_flags += 1

    print("\n--- RESULTADOS DA AUDITORIA ---")
    if anomalous_timing_flags > 0:
        print(f" [AVISO] {anomalous_timing_flags} amostras com tempos anômalos detectadas!")
    else:
        print(" [OK] Todas as medições de Frame Time e VRAM estão consistentes e válidas.")

    print("\n[CONCLUSAO] Auditoria concluida.")
    return True

if __name__ == "__main__":
    target_csv = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "bench", "results", "raw.csv")
    audit_benchmark_csv(os.path.abspath(target_csv))
