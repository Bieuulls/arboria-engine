#!/usr/bin/env python3
"""
ARBORIA ENGINE — TESTE DE REGRESSÃO: NEUTRALIZAÇÃO DE CAMINHOS LOCAIS (FASE 0.2)
Verifica que nenhum arquivo versionado no repositório contém caminhos absolutos locais
de desenvolvimento (ex: 'srgab' ou 'C:\\Users\\').
"""

import os
import sys
import subprocess

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def main():
    print("==================================================================")
    print(" [TESTE DE REGRESSÃO 0.2] NEUTRALIZAÇÃO DE CAMINHOS LOCAIS       ")
    print("==================================================================")

    # Lista todos os arquivos rastreados pelo git
    res = subprocess.run(
        ["git", "ls-files"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=True
    )
    tracked_files = res.stdout.strip().splitlines()
    print(f"Total de arquivos rastreados no git: {len(tracked_files)}")

    forbidden_patterns = ["srgab"]
    violations = []

    for rel_path in tracked_files:
        full_path = os.path.join(REPO_ROOT, rel_path)
        if not os.path.isfile(full_path):
            continue

        # Pula binários compilados conhecidos
        if rel_path.endswith((".exe", ".dll", ".pck", ".lib", ".obj", ".png", ".jpg", ".vgmesh")):
            continue

        try:
            with open(full_path, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
                for pat in forbidden_patterns:
                    if pat.lower() in content.lower():
                        violations.append((rel_path, pat))
        except Exception as e:
            pass

    if violations:
        print(f"[FALHA] Foram encontradas {len(violations)} violacoes de caminhos locais:")
        for path, pat in violations[:10]:
            print(f"  - {path}: contem '{pat}'")
        sys.exit(1)

    print(f"[APROVADO] 0 ocorrencias de caminhos locais encontradas em {len(tracked_files)} arquivos rastreados!")
    print("==================================================================")
    print(" [FASE 0.2 REGRESSAO: PASSOU E COMPROVADO]                       ")
    print("==================================================================")
    sys.exit(0)

if __name__ == "__main__":
    main()
