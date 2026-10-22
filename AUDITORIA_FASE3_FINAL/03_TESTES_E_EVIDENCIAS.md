# RELATÓRIO 03 — TESTES E EVIDÊNCIAS
**Data:** 21 de Outubro de 2026  
**Diretório:** `D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL`  
**Responsável:** Engenheiro de Renderização (ARBORIA ENGINE Core)

---

## 1. COMANDOS DE REPRODUÇÃO

Todos os testes podem ser reproduzidos de forma determinística executando os seguintes comandos a partir da raiz do repositório (`D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL`):

```powershell
# 1. Bateria C++ de Validação Lossless LOD 0 e Corrupção Binária (17 testes)
python tests/test_suite.py

# 2. Testes Negativos Obrigatórios do Pipeline GPU e Desenho Indireto (P0)
d:\ARBORIA_ENGINE\bin\godot_console.exe --path project -s scripts/test_p0_negative_tests.gd

# 3. Validação Visual e Geométrica Rigorosa em 9 Cenários (P1)
d:\ARBORIA_ENGINE\bin\godot_console.exe --path project -s scripts/test_visual_validation.gd

# 4. Benchmark Comparativo Rigoroso (4 cenários x 420 frames) (P0)
d:\ARBORIA_ENGINE\bin\godot_console.exe --path project -s scripts/benchmark_fase3.gd
```

---

## 2. RESULTADOS DOS TESTES NEGATIVOS OBRIGATÓRIOS (P0)

Executado via `test_p0_negative_tests.gd`. O pipeline consome o buffer `counter_buf` de `VkDrawIndirectCommand` emitido pelo Compute Shader para desenhar geometria real via `rd.draw_list_draw_indirect`.

| Teste Negativo | Procedimento | Comportamento Esperado | Resultado Observado | Status |
|---|---|---|---|---|
| **Teste A: Desativar Desenho Indireto** | Desabilita a submissão de desenho indireto mantendo o pipeline ativo. | Geometria ARBORIA deve desaparecer completamente (0 pixels). | **0 pixels renderizados** | **APROVADO** |
| **Teste B: `instance_count = 0`** | Força zero instâncias no comando indireto da GPU. | Nenhum triângulo ARBORIA desenhado (0 pixels). | **0 pixels renderizados** | **APROVADO** |
| **Teste C: Alteração de Geometria** | Troca a malha em runtime de `dense_rock` para `boulder_granite`. | O desenho indireto reflete a nova geometria com contagem de pixels distinta. | **5.095 pixels (35.659 px de diferença comprovada)** | **APROVADO** |
| **Teste D: Seleção de LOD Dinâmica GPU** | Câmera posicionada a 8m (near) vs 35m (far). | Quantidade de clusters selecionados deve mudar sem intervenção da CPU. | **Near: 153 instâncias \| Far: 49 instâncias** | **APROVADO** |
| **Teste E: Redução Real de Trabalho GPU** | Compara invocações de vértices entre MultiMesh fixo legado e Indireto GPU. | Clusters descartados não devem processar vértices na chamada indireta. | **Legado: 140.928 vértices \| Indireto: 18.816 vértices (-86.6% trabalho real)** | **APROVADO** |

**Evidência Gravada:**
- `AUDITORIA_FASE3_FINAL/evidencias/indirect_draw_real_geom.png` (Captura offscreen com 35.663 pixels renderizados).
- `AUDITORIA_FASE3_FINAL/evidencias/neg_test_A_disabled.png` (Tela vazia com 0 pixels).

---

## 3. RESULTADOS DA BATERIA DE VALIDAÇÃO VISUAL (P1)

Executado via `test_visual_validation.gd` em 9 cenários comparando a referência convencional com a saída do pipeline ARBORIA sob Vulkan Forward+ em resolução 512x512.

| # | Cenário de Teste | Parâmetros de Câmera / Shading | Ref (px) | GPU (px) | Silhueta IoU | Cobertura | Delta RGB | Buracos | Status |
|---|---|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **1** | `1_Closeup_LOD0_Unshaded` | Dist: 9.5m, FOV: 65°, Unshaded | 78.560 | 78.560 | **100.0%** | **100.0%** | 0.0080 | 0 | **APROVADO** |
| **2** | `2_Closeup_LOD0_PBR` | Dist: 9.5m, FOV: 65°, Lit PBR | 78.560 | 78.560 | **100.0%** | **100.0%** | 0.0101 | 0 | **APROVADO** |
| **3** | `3_Mid_Mixed_DAG_Unshaded` | Dist: 16.0m, FOV: 70°, DAG LOD | 21.317 | 21.282 | **99.8%** | **99.8%** | 0.0029 | 0 | **APROVADO** |
| **4** | `4_Distant_LOD` | Dist: 32.0m, FOV: 70°, Coarse LOD | 5.544 | 5.526 | **99.3%** | **99.7%** | 0.0499 | 0 | **APROVADO** |
| **5** | `5_Wide_FOV_90` | Dist: 10.0m, FOV: 90° grande angular | 29.643 | 29.620 | **99.8%** | **99.9%** | 0.0484 | 0 | **APROVADO** |
| **6** | `6_Narrow_FOV_30` | Dist: 22.0m, FOV: 30° teleobjetiva | 72.182 | 72.182 | **100.0%** | **100.0%** | 0.0677 | 0 | **APROVADO** |
| **7** | `7_Camera_Rotation` | Dist: 12.0m, Yaw: 4.5 rad, Pitch: -0.5 | 51.902 | 51.902 | **100.0%** | **100.0%** | 0.1630 | 0 | **APROVADO** |
| **8** | `8_Frustum_Culled_Away` | Câmera olhando 180° de costas | 0 | 0 | **0.0%** | **0.0%** | 0.0000 | 0 | **APROVADO (0 px vazados)** |
| **9** | `9_Temporal_Motion_Check` | Movimento contínuo de rotação/pitch | 69.241 | 69.241 | **100.0%** | **100.0%** | 0.0057 | 0 | **APROVADO** |

**Evidências Gravadas (27 imagens em `AUDITORIA_FASE3_FINAL/evidencias/visual/`):**
- Referência, GPU e Mapa de Diferenças para cada um dos 9 cenários (`*_ref.png`, `*_gpu.png`, `*_diff.png`).
- Confirmação de ausência de pixels pretos inesperados em superfícies opacas em todos os testes.

---

## 4. RESULTADOS DA BATERIA DE TESTES C++ E BAKER (P1)

Executado via `tests/test_suite.py` com o binário `bin/vg_baker_cli.exe`.

```
================================================================================
ARBORIA VIRTUAL GEOMETRY — BATERIA DE TESTES DE INTEGRIDADE & VALIDACAO (FASE 3)
================================================================================
[APROVADO ] 1. Binario C++ Compilado
  -> vg_baker_cli.exe presente (435,712 bytes)
[APROVADO ] 2. Malha Pequena (512 triangulos) + Reconstrucao
  -> Exit code: 0 | Verificacao profunda de integridade 100% aprovada
[APROVADO ] 3. Malha Densa (16.000 triangulos) + Hierarquia DAG Multi-LOD
  -> Exit code: 0 | 367 clusters gerados com limites estritos (<=64 verts, <=128 tris)
[APROVADO ] 4. Tratamento de Arquivo Inexistente
  -> Capturou erro corretamente (Exit code 2): Nao foi possivel abrir o arquivo
[APROVADO ] 5. Tratamento de Arquivo Corrompido / Sem Faces
  -> Rejeitou malha vazia/sem faces corretamente (Exit code 2)
[APROVADO ] 6. Rejeicao de Referencias Invalidas de UV/Normal (Indice 999 OOB)
  -> Rejeitou indices OOB com seguranca (Exit code 2) e mensagem explicita
[APROVADO ] 7. Rejeicao de Binario .vgmesh Truncado / Adulterado
  -> Detectou e rejeitou binario truncado/invalido com seguranca
[APROVADO ] 8. Validacao Estrutural do Binario .vgmesh v2 + DAG Groups
  -> Magic: ARBORIA2 | Versao: 2 | Tris: 31,494 | Clusters: 367 | LODs: 9 | DAG Groups: 27
[APROVADO ] 9. Integridade de Vinculos Hierarquicos DAG
  -> Todos os 367 clusters possuem vinculos validos com 27 grupos DAG (limites <=64v, <=128t respeitados)
[APROVADO ] 10. Corrupcao: Header Truncado (< 72 bytes)
  -> Rejeitado com seguranca (Exit Code 4) | ERRO: Tamanho de arquivo (30 bytes) menor que cabecalho
[APROVADO ] 11. Corrupcao: Payload Truncado
  -> Rejeitado com seguranca (Exit Code 4) | ERRO: Arquivo truncado! Tamanho no disco: 500 bytes
[APROVADO ] 12. Corrupcao: Offsets Alem do Fim do Arquivo
  -> Rejeitado com seguranca (Exit Code 4) | ERRO: Cluster 0 vertex_offset + count (999999 + 64) excede buffer
[APROVADO ] 13. Corrupcao: Contagens Inconsistentes de Clusters no LOD
  -> Rejeitado com seguranca (Exit Code 4) | ERRO: LOD 0 cluster_offset + count excede cluster_count!
[APROVADO ] 14. Corrupcao: Indices de Clusters Invalidos (> vertex_count)
  -> Rejeitado com seguranca (Exit Code 4) | Rejeitado por validacao de limites de triangulos
[APROVADO ] 15. Corrupcao: Referencias DAG Invalidas (group_id OOB)
  -> Rejeitado com seguranca (Exit Code 4) | ERRO: Cluster 0 referencia group_id (99999) invalido!
[APROVADO ] 16. Corrupcao: Magic Invalido / Incoerente
  -> Rejeitado com seguranca (Exit Code 4) | ERRO: Magic invalido no .vgmesh (esperado ARBORIA2)!
[APROVADO ] 17. LOD 0 Lossless Validado (Vertices, AABB, Normais, UVs, Orientacao)
  -> 100% dos triangulos, vertices, normais e UVs equivalentes geometricamente entre OBJ e LOD 0
================================================================================
TOTAL: 17 TESTES EXECUTADOS | 17 APROVADOS | 0 FALHAS
================================================================================
```
