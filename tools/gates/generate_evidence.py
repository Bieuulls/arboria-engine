#!/usr/bin/env python3
"""
ARBORIA ENGINE — GATE: GENERATE EVIDENCE (tools/gates/generate_evidence.py)
Gera o relatório padronizado e auditável JSON de aprovação de gate.
"""

import sys
import os
import json
import subprocess
import argparse

def get_git_commit(repo_root: str) -> str:
    try:
        res = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo_root, capture_output=True, text=True, check=True)
        return res.stdout.strip()
    except Exception:
        return "UNKNOWN_COMMIT"

def main():
    parser = argparse.ArgumentParser(description="Gera JSON de evidência oficial do Gate")
    parser.add_argument("--stage", required=True, help="Número do stage (ex: 00, 01, ...)")
    parser.add_argument("--status", choices=["PASSED", "FAILED", "BLOCKED", "NOT_STARTED"], required=True)
    parser.add_argument("--build", default="NOT_RUN", help="Status do build (PASSED/FAILED/NOT_RUN)")
    parser.add_argument("--runtime", default="NOT_RUN", help="Status do runtime (PASSED/FAILED/NOT_RUN)")
    parser.add_argument("--geometry", default="NOT_RUN", help="Status geométrico (PASSED/FAILED/NOT_RUN)")
    parser.add_argument("--gpu", default="NOT_RUN", help="Status GPU (PASSED/FAILED/NOT_RUN)")
    parser.add_argument("--regressions", default="NOT_RUN", help="Status regressões (PASSED/FAILED/NOT_RUN)")
    parser.add_argument("--evidence", nargs="*", default=[], help="Caminhos de arquivos de evidência")
    parser.add_argument("--blocking-errors", nargs="*", default=[], help="Lista de mensagens de erros bloqueantes")
    parser.add_argument("--output", help="Caminho do arquivo de saída JSON (padrão: artifacts/gates/stage_XX/gate_result.json)")
    args = parser.parse_args()

    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    commit_sha = get_git_commit(repo_root)

    report = {
        "stage": args.stage,
        "status": args.status,
        "commit": commit_sha,
        "build": args.build,
        "runtime": args.runtime,
        "geometry": args.geometry,
        "gpu": args.gpu,
        "regressions": args.regressions,
        "evidence": args.evidence,
        "blocking_errors": args.blocking_errors
    }

    out_path = args.output
    if not out_path:
        out_dir = os.path.join(repo_root, "artifacts", "gates", f"stage_{args.stage}")
        os.makedirs(out_dir, exist_ok=True)
        out_path = os.path.join(out_dir, "gate_result.json")

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)

    print(f"[GENERATE EVIDENCE] Relatório de Gate salvo em: {out_path}")
    print(json.dumps(report, indent=2))

if __name__ == "__main__":
    main()
