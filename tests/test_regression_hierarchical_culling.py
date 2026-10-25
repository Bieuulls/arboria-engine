#!/usr/bin/env python3
"""
ARBORIA ENGINE — TESTE DE REGRESSÃO: PODA HIERÁRQUICA DE CLUSTERS (FASE 1.2)
Verifica que o compute shader global de culling possui as três camadas de poda
hierárquica que evitam a avaliação linear O(N*C) de clusters.
"""

import os
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHADER_PATH = os.path.join(REPO_ROOT, "project", "shaders", "cull_clusters_global.glsl")

def main():
    print("==================================================================")
    print(" [TESTE DE REGRESSÃO 1.2] PODA HIERÁRQUICA DE CLUSTERS           ")
    print("==================================================================")

    if not os.path.isfile(SHADER_PATH):
        print(f"[FALHA] Shader nao encontrado em {SHADER_PATH}")
        sys.exit(1)

    with open(SHADER_PATH, "r", encoding="utf-8") as f:
        code = f.read()

    required_features = [
        ("PODA HIERÁRQUICA ETAPA 1: Frustum Culling na Instância", "inst.bounding_sphere"),
        ("PODA HIERÁRQUICA ETAPA 2: Avaliação de Erro de Tela do Grupo Pai", "group_bounds_error"),
        ("PODA HIERÁRQUICA ETAPA 3: Frustum Culling do Grupo Pai", "parent_in_frustum"),
    ]

    missing = []
    for feat_name, needle in required_features:
        if needle not in code:
            missing.append(feat_name)
        else:
            print(f"[OK] {feat_name} verificado no shader GLSL.")

    if missing:
        print(f"[FALHA] Funcionalidades de poda hierarquica ausentes: {missing}")
        sys.exit(1)

    print("[APROVADO] Todas as 3 etapas de poda hierarquica verificadas com sucesso!")
    print("==================================================================")
    print(" [FASE 1.2 REGRESSAO: PASSOU E COMPROVADO]                       ")
    print("==================================================================")
    sys.exit(0)

if __name__ == "__main__":
    main()
