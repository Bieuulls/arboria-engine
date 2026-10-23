#!/usr/bin/env python3
"""
ARBORIA ENGINE — GATE: VALIDATE RESOURCES (tools/gates/validate_resources.py)
Valida vazamentos de recursos GPU (RIDs), memória e handles a partir de logs de saída.
"""

import sys
import os
import re
import argparse

def validate_resources(log_file: str, max_leaks: int = 50) -> bool:
    if not os.path.exists(log_file):
        print(f"[FAIL] Arquivo de log não encontrado: {log_file}", file=sys.stderr)
        return False

    with open(log_file, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    leaks = re.findall(r"WARNING:\s*(\d+)\s*RIDs of type \"([^\"]+)\" were leaked", content)
    total_leaked = 0
    if leaks:
        print("[VALIDATE RESOURCES] RIDs informados como vazados ao encerrar:")
        for count, rid_type in leaks:
            c = int(count)
            total_leaked += c
            print(f"  -> {c} RIDs de '{rid_type}'")

    obj_leaks = re.findall(r"WARNING:\s*(\d+)\s*ObjectDB instance was leaked", content)
    for count in obj_leaks:
        print(f"  -> {count} instâncias do ObjectDB vazadas")

    if total_leaked > max_leaks:
        print(f"[FAIL] Total de RIDs vazados ({total_leaked}) excede o limite máximo permitido ({max_leaks})", file=sys.stderr)
        return False

    print(f"[VALIDATE RESOURCES] Verificação concluída. Total de RIDs vazados: {total_leaked} (limite: {max_leaks})")
    return True

def main():
    parser = argparse.ArgumentParser(description="Validação de integridade de recursos e ausência de vazamentos")
    parser.add_argument("log_file", help="Caminho para o log de execução")
    parser.add_argument("--max-leaks", type=int, default=50, help="Máximo tolerável de RIDs vazados no encerramento")
    args = parser.parse_args()

    passed = validate_resources(args.log_file, args.max_leaks)
    sys.exit(0 if passed else 1)

if __name__ == "__main__":
    main()
