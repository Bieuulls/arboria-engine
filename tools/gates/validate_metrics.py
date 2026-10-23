#!/usr/bin/env python3
"""
ARBORIA ENGINE — GATE: VALIDATE METRICS (tools/gates/validate_metrics.py)
Valida métricas operacionais e de telemetria a partir de logs ou arquivos JSON de gates.
"""

import sys
import os
import re
import json
import argparse

def parse_log_metrics(log_file: str) -> dict:
    metrics = {
        "clusters_evaluated": None,
        "clusters_visible": None,
        "triangles_drawn": None,
        "instances": None,
        "errors": 0,
        "crashes": 0
    }

    if not os.path.exists(log_file):
        print(f"[FAIL] Arquivo de log nao encontrado: {log_file}", file=sys.stderr)
        return metrics

    with open(log_file, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    # Padrões comuns de telemetria no Godot / ARBORIA
    m_clusters = re.findall(r"Clusters\s*(?:Vis[ií]veis)?\s*[:=]\s*(\d+)", content, re.IGNORECASE)
    if m_clusters:
        metrics["clusters_visible"] = int(m_clusters[-1])

    m_tris = re.findall(r"Tri[aâ]ngulos\s*(?:desenhados)?\s*[:=]\s*(\d+)", content, re.IGNORECASE)
    if m_tris:
        metrics["triangles_drawn"] = int(m_tris[-1])

    m_inst = re.findall(r"Inst[aâ]ncias\s*[:=]\s*(\d+)", content, re.IGNORECASE)
    if m_inst:
        metrics["instances"] = int(m_inst[-1])

    errors = re.findall(r"(?:SCRIPT ERROR|ERROR:|\bCRASH\b|Segmentation fault)", content)
    metrics["errors"] = len(errors)

    return metrics

def validate_metrics(metrics: dict, require_clusters: bool = True, max_errors: int = 0) -> bool:
    print(f"[VALIDATE METRICS] Métricas extraídas: {json.dumps(metrics, indent=2)}")

    if metrics.get("errors", 0) > max_errors:
        print(f"[FAIL] Erros encontrados no log: {metrics['errors']} > {max_errors}", file=sys.stderr)
        return False

    if require_clusters:
        c_vis = metrics.get("clusters_visible")
        if c_vis is None or c_vis <= 0:
            print(f"[FAIL] Clusters visíveis inválidos: {c_vis}", file=sys.stderr)
            return False

        t_drawn = metrics.get("triangles_drawn")
        if t_drawn is None or t_drawn <= 0:
            print(f"[FAIL] Triângulos desenhados inválidos: {t_drawn}", file=sys.stderr)
            return False

    return True

def main():
    parser = argparse.ArgumentParser(description="Validação de métricas operacionais para gates")
    parser.add_argument("log_file", help="Caminho para o log de execução")
    parser.add_argument("--no-require-clusters", action="store_true", help="Não exigir contagem positiva de clusters")
    parser.add_argument("--max-errors", type=int, default=0, help="Máximo tolerável de mensagens de erro")
    args = parser.parse_args()

    metrics = parse_log_metrics(args.log_file)
    passed = validate_metrics(metrics, not args.no_require_clusters, args.max_errors)
    sys.exit(0 if passed else 1)

if __name__ == "__main__":
    main()
