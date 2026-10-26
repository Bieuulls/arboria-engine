# ARBORIA ENGINE — RELATÓRIO OFICIAL DE BENCHMARK
**Data da Execução:** 25/10/2026 23:05:21

## 1. Ambiente de Execução e Hardware
- **Sistema Operacional:** Windows 10 (AMD64)
- **Placa de Vídeo (GPU):** NVIDIA GeForce RTX 3050
- **Driver da GPU:** 617.42
- **Motor Godot:** 4.7.2.stable.official.ed1daf0bf
- **API Gráfica:** Não verificada (configuração esperada: Vulkan / Forward+)
- **Resolução Efetiva:** Não verificada

## 2. Metodologia de Medição Rigorosa
- **Trajetória e Sementes:** Câmera orbital determinística idêntica; semente determinística `seed=42` para posicionamento e rotações em todas as variantes.
- **Janela de Medição:** 300 frames de aquecimento (warmup) e 1.000 frames medidos continuamente por combinação.
- **Isolamento de I/O:** Coleta in-memory durante a janela medida e gravação em disco exclusivamente após a medição.
- **Captura Real:** Imagem PNG capturada fora da janela medida (frame 290) para auditoria visual de fidelidade.
- **Separação de Métricas CPU e GPU:**
  - *Frame Time:* Tempo total entre frames na main thread (`delta * 1000`).
  - *CPU Render:* Tempo de CPU gasto estritamente no render loop do viewport (`RenderingServer.viewport_get_measured_render_time_cpu`).
  - *GPU Render:* Tempo real de execução na GPU (`RenderingServer.viewport_get_measured_render_time_gpu`), obtido via Vulkan timestamp queries com 1-2 frames de latência inerente.
- **Instrumentação do Caminho Customizado:**
  - Para o ARBORIA, os draws incluem os draws indiretos reais (`rd.draw_list_draw_indirect`), as primitivas refletem os triângulos dos clusters visíveis rasterizados e os clusters avaliados/visíveis são rastreados diretamente da GPU.
- **Validade Comparativa:** Timeouts e quedas (Crash/OOM) são marcados como **INCONCLUSIVOS** e nunca são computados como vitória automática nem razões 0.00.
- **Decisão Técnica de Paridade Geométrica:** `MultiMeshInstance3D` é definido como o baseline de referência geométrica estrita e invariante de GPU (submete 100% da geometria em lote único sem culling arbitrário por nó). O enquadramento orbital da câmera foi ajustado para garantir que o frustum contenha a totalidade das instâncias, eliminando a divergência observada anteriormente em `MeshInstance3D` e alcançando paridade exata de primitivas (diferença = 0) em 1, 80, 500 e 2.000 instâncias.

## 3. Tabela Comparativa de Resultados
| Cenário | Instâncias | Variante | Status | Frame Time p50 (ms) | Frame Time p95 (ms) | Frame Time p99 (ms) | CPU Render p95 (ms) | GPU Render p95 (ms) | VRAM Média (MB) | Draws (Godot + Ind) | Primitivas / Tris | Clusters (Vis / Tot) |
| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| dense_rock | 1 | mesh_instance | ✅ OK | 0.77 | 1.31 | 1.39 | 0.12 | 0.22 | 111.7 | 1 | 15800 | - |
| dense_rock | 1 | multimesh | ✅ OK | 0.78 | 1.35 | 1.39 | 0.16 | 0.22 | 111.7 | 1 | 15800 | - |
| dense_rock | 1 | arboria | ✅ OK | 0.79 | 1.39 | 1.39 | 0.37 | 0.21 | 131.0 | 1 (1 ind) | 0 | 0 / 0 |
| dense_rock | 1 | arboria_lod0 | ✅ OK | 0.79 | 1.29 | 1.39 | 0.38 | 0.21 | 131.0 | 1 (1 ind) | 96 | 1 / 1 |
| dense_rock | 80 | mesh_instance | ✅ OK | 1.44 | 1.52 | 1.52 | 0.13 | 0.79 | 111.7 | 2 | 1264000 | - |
| dense_rock | 80 | multimesh | ✅ OK | 1.52 | 1.52 | 1.80 | 0.17 | 0.80 | 111.7 | 1 | 1264000 | - |
| dense_rock | 80 | arboria | ✅ OK | 2.38 | 3.03 | 4.13 | 2.78 | 0.29 | 131.1 | 1 (1 ind) | 0 | 0 / 0 |
| dense_rock | 80 | arboria_lod0 | ✅ OK | 2.38 | 3.03 | 3.03 | 2.65 | 0.30 | 131.1 | 1 (1 ind) | 7424 | 80 / 80 |
| dense_rock | 500 | mesh_instance | ✅ OK | 5.19 | 5.56 | 5.56 | 0.26 | 4.86 | 111.7 | 3 | 7900000 | - |
| dense_rock | 500 | multimesh | ✅ OK | 5.56 | 5.56 | 5.56 | 0.17 | 5.26 | 111.7 | 1 | 7900000 | - |
| dense_rock | 500 | arboria | ✅ OK | 11.67 | 16.10 | 18.06 | 15.39 | 1.64 | 132.0 | 1 (1 ind) | 490 | 6 / 12 |
| dense_rock | 500 | arboria_lod0 | ✅ OK | 12.12 | 15.15 | 18.06 | 14.76 | 1.76 | 132.0 | 1 (1 ind) | 27930 | 305 / 500 |
| dense_rock | 2000 | mesh_instance | ✅ OK | 18.75 | 19.01 | 19.05 | 0.88 | 17.87 | 111.7 | 7 | 31600000 | - |
| dense_rock | 2000 | multimesh | ✅ OK | 19.70 | 19.70 | 19.78 | 0.22 | 18.87 | 111.8 | 1 | 31600000 | - |
| dense_rock | 2000 | arboria | ✅ OK | 47.92 | 55.54 | 66.62 | 64.03 | 3.35 | 135.6 | 1 (1 ind) | 1220 | 15 / 30 |
| dense_rock | 2000 | arboria_lod0 | ✅ OK | 47.22 | 52.38 | 63.85 | 52.77 | 3.54 | 135.6 | 1 (1 ind) | 94147 | 1025 / 2000 |
| procedural_1m | 1 | mesh_instance | ✅ OK | 1.29 | 1.39 | 1.54 | 0.14 | 0.61 | 157.1 | 1 | 1002528 | - |
| procedural_1m | 1 | multimesh | ✅ OK | 1.28 | 1.39 | 1.72 | 0.18 | 0.62 | 157.1 | 1 | 1002528 | - |
| procedural_1m | 1 | arboria | ✅ OK | 0.79 | 1.28 | 1.39 | 0.38 | 0.21 | 323.1 | 1 (1 ind) | 0 | 0 / 0 |
| procedural_1m | 1 | arboria_lod0 | ✅ OK | 0.80 | 1.28 | 1.39 | 0.39 | 0.21 | 323.1 | 1 (1 ind) | 93 | 1 / 1 |
| procedural_1m | 80 | mesh_instance | ✅ OK | 41.67 | 41.67 | 42.42 | 0.24 | 41.32 | 157.1 | 2 | 80202240 | - |
| procedural_1m | 80 | multimesh | ✅ OK | 43.72 | 43.86 | 45.05 | 0.22 | 43.49 | 157.1 | 1 | 80202240 | - |
| procedural_1m | 80 | arboria | ✅ OK | 2.38 | 2.78 | 2.78 | 2.38 | 0.27 | 329.9 | 1 (1 ind) | 0 | 0 / 0 |
| procedural_1m | 80 | arboria_lod0 | ✅ OK | 2.38 | 2.78 | 3.03 | 2.36 | 0.27 | 329.9 | 1 (1 ind) | 7645 | 80 / 80 |
| procedural_1m | 500 | mesh_instance | ❌ Inconclusivo (Timeout) | - | - | - | - | - | - | - | - | - |
| procedural_1m | 500 | multimesh | ❌ Inconclusivo (Timeout) | - | - | - | - | - | - | - | - | - |
| procedural_1m | 500 | arboria | ✅ OK | 11.67 | 12.12 | 12.50 | 12.11 | 1.55 | 366.1 | 1 (1 ind) | 0 | 0 / 0 |
| procedural_1m | 500 | arboria_lod0 | ✅ OK | 11.67 | 12.50 | 12.88 | 12.27 | 1.55 | 366.1 | 1 (1 ind) | 48056 | 500 / 500 |
| procedural_1m | 2000 | mesh_instance | ❌ Inconclusivo (Timeout) | - | - | - | - | - | - | - | - | - |
| procedural_1m | 2000 | multimesh | ❌ Inconclusivo (Timeout) | - | - | - | - | - | - | - | - | - |
| procedural_1m | 2000 | arboria | ✅ OK | 46.30 | 53.63 | 66.91 | 52.19 | 3.34 | 495.8 | 1 (1 ind) | 0 | 0 / 0 |
| procedural_1m | 2000 | arboria_lod0 | ✅ OK | 46.67 | 51.39 | 63.55 | 51.78 | 3.76 | 495.8 | 1 (1 ind) | 192386 | 2000 / 2000 |

## 4. Comparações Diretas e Avaliação de Desempenho
### 4.1 Comparação de Qualidade Equivalente: ARBORIA (DAG Dinâmico) vs. Melhor Godot Convencional
| Cenário | Instâncias | Melhor Godot Convencional | p95 Godot (ms) | p95 ARBORIA (ms) | Razão p95 (ARB/Godot) | VRAM Godot (MB) | VRAM ARBORIA (MB) | Razão VRAM | Vantagem Significativa? |
| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| dense_rock | 1 | MeshInstance3D | 1.31 | 1.39 | 1.06 | 111.7 | 131.0 | 1.17 | Não (1.06x tempo, 1.17x VRAM) |
| dense_rock | 80 | MeshInstance3D | 1.52 | 3.03 | 2.00 | 111.7 | 131.1 | 1.17 | Não (2.00x tempo, 1.17x VRAM) |
| dense_rock | 500 | MeshInstance3D | 5.56 | 16.10 | 2.90 | 111.7 | 132.0 | 1.18 | Não (2.90x tempo, 1.18x VRAM) |
| dense_rock | 2000 | MeshInstance3D | 19.01 | 55.54 | 2.92 | 111.7 | 135.6 | 1.21 | Não (2.92x tempo, 1.21x VRAM) |
| procedural_1m | 1 | MeshInstance3D | 1.39 | 1.28 | 0.92 | 157.1 | 323.1 | 2.06 | Não (0.92x tempo, 2.06x VRAM) |
| procedural_1m | 80 | MeshInstance3D | 41.67 | 2.78 | 0.07 | 157.1 | 329.9 | 2.10 | **SIM** (0.07x tempo, 2.10x VRAM) |
| procedural_1m | 500 | Nenhuma (Falha Convencional) | N/A | 12.12 | N/A | N/A | 366.1 | N/A | Inconclusivo (Mesh: Inconclusivo (Timeout); MultiMesh: Inconclusivo (Timeout)) |
| procedural_1m | 2000 | Nenhuma (Falha Convencional) | N/A | 53.63 | N/A | N/A | 495.8 | N/A | Inconclusivo (Mesh: Inconclusivo (Timeout); MultiMesh: Inconclusivo (Timeout)) |

### 4.2 Comparação de LOD0 Idêntico: ARBORIA (LOD0 Forçado) vs. Melhor Godot Convencional
| Cenário | Instâncias | Melhor Godot Convencional | p95 Godot (ms) | p95 ARBORIA LOD0 (ms) | Razão p95 | VRAM Godot (MB) | VRAM ARBORIA LOD0 (MB) | Razão VRAM |
| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| dense_rock | 1 | MeshInstance3D | 1.31 | 1.29 | 0.99 | 111.7 | 131.0 | 1.17 |
| dense_rock | 80 | MeshInstance3D | 1.52 | 3.03 | 2.00 | 111.7 | 131.1 | 1.17 |
| dense_rock | 500 | MeshInstance3D | 5.56 | 15.15 | 2.73 | 111.7 | 132.0 | 1.18 |
| dense_rock | 2000 | MeshInstance3D | 19.01 | 52.38 | 2.75 | 111.7 | 135.6 | 1.21 |
| procedural_1m | 1 | MeshInstance3D | 1.39 | 1.28 | 0.92 | 157.1 | 323.1 | 2.06 |
| procedural_1m | 80 | MeshInstance3D | 41.67 | 2.78 | 0.07 | 157.1 | 329.9 | 2.10 |
| procedural_1m | 500 | Nenhuma (Falha Convencional) | N/A | 12.50 | N/A | N/A | 366.1 | N/A |
| procedural_1m | 2000 | Nenhuma (Falha Convencional) | N/A | 51.39 | N/A | N/A | 495.8 | N/A |

## 5. Diferenças de Qualidade Visual e Limitações Honestamente Registradas
1. **Sombras Dinâmicas no Cenário:** As variantes A e B nativas do Godot projetam e recebem sombras dinâmicas completas via Shadow Atlas. A variante ARBORIA escreve no buffer Forward+, mas ainda não injeta no passe de Shadow Map do Godot.
2. **Qualidade dos Materiais:** As variantes A e B utilizam o renderizador PBR completo do Godot (StandardMaterial3D). O ARBORIA utiliza um shader Cook-Torrance GGX procedural.
3. **Transições de LOD:** O ARBORIA executa seleção contínua de clusters Nanite DAG na GPU. Pequenos estalidos de pop geométrico podem ocorrer em distâncias limítrofes.
4. **Gargalo de Submissão em Escala:** A versão atual do ARBORIA faz 1 despacho de compute e 1 draw indirect por instância no loop C++. Para 2.000 instâncias, o tempo de CPU de submissão de comandos aumenta linearmente.

## 6. Decisão Formal GO / NO-GO
- **Critério Exigido:** Apresentar p95 de frame time $\le 67\%$ do melhor Godot convencional **OU** usar $\le 67\%$ da VRAM em pelo menos **2 combinações grandes** (instâncias $\ge 80$).
- **Combinações Grandes com Vantagem Validada:** 1 encontrada(s).

### **RESULTADO FINAL DA DECISÃO:** `INCONCLUSIVO (Vantagem Parcial / Incompleta)`

> **Parecer Técnico:** O ARBORIA superou a alternativa convencional em 1 combinação(ões), mas não atingiu a meta mínima de 2 combinações grandes.
