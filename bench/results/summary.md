# ARBORIA ENGINE — RELATÓRIO OFICIAL DE BENCHMARK
**Data da Execução:** 25/10/2026 14:29:28

## 1. Ambiente de Execução e Hardware
- **Sistema Operacional:** Windows 10 (AMD64)
- **Placa de Vídeo (GPU):** NVIDIA GeForce RTX 3050
- **Driver da GPU:** 617.42
- **Motor Godot:** 4.7.2.stable.official.ed1daf0bf
- **API Gráfica:** Vulkan 1.4 / Forward+
- **Resolução Efetiva:** 1920x1080 (VSync OFF, FPS Ilimitado)

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
| dense_rock | 1 | mesh_instance | ✅ OK | 0.90 | 1.24 | 1.29 | 0.19 | 0.26 | 111.7 | 1 | 15800 | - |
| dense_rock | 1 | multimesh | ✅ OK | 0.91 | 1.67 | 1.67 | 0.11 | 0.26 | 111.7 | 1 | 15800 | - |
| dense_rock | 1 | arboria | ✅ OK | 0.88 | 1.15 | 1.30 | 0.31 | 0.26 | 130.2 | 1 (1 ind) | 3866 | 47 / 367 |
| dense_rock | 1 | arboria_lod0 | ✅ OK | 0.92 | 1.85 | 1.85 | 0.26 | 0.27 | 130.2 | 1 (1 ind) | 15800 | 172 / 367 |
| dense_rock | 500 | mesh_instance | ✅ OK | 5.91 | 6.69 | 7.08 | 0.24 | 6.09 | 111.7 | 3 | 7900000 | - |
| dense_rock | 500 | multimesh | ✅ OK | 6.67 | 7.24 | 7.26 | 0.27 | 6.36 | 111.7 | 1 | 7900000 | - |
| dense_rock | 500 | arboria | ✅ OK | 6.64 | 8.06 | 8.33 | 7.01 | 0.63 | 131.1 | 1 (1 ind) | 337374 | 4137 / 183500 |
| dense_rock | 500 | arboria_lod0 | ✅ OK | 6.67 | 8.31 | 8.33 | 6.52 | 7.50 | 131.1 | 1 (1 ind) | 7900000 | 86000 / 183500 |

## 4. Comparações Diretas e Avaliação de Desempenho
### 4.1 Comparação de Qualidade Equivalente: ARBORIA (DAG Dinâmico) vs. Melhor Godot Convencional
| Cenário | Instâncias | Melhor Godot Convencional | p95 Godot (ms) | p95 ARBORIA (ms) | Razão p95 (ARB/Godot) | VRAM Godot (MB) | VRAM ARBORIA (MB) | Razão VRAM | Vantagem Significativa? |
| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| dense_rock | 1 | MeshInstance3D | 1.24 | 1.15 | 0.93 | 111.7 | 130.2 | 1.17 | Não (0.93x tempo, 1.17x VRAM) |
| dense_rock | 500 | MeshInstance3D | 6.69 | 8.06 | 1.21 | 111.7 | 131.1 | 1.17 | Não (1.21x tempo, 1.17x VRAM) |
| pine_trunk | 1 | - | - | - | N/A | - | - | N/A | Inconclusivo (ARBORIA Ausente) |
| pine_trunk | 80 | - | - | - | N/A | - | - | N/A | Inconclusivo (ARBORIA Ausente) |
| pine_trunk | 500 | - | - | - | N/A | - | - | N/A | Inconclusivo (ARBORIA Ausente) |
| pine_trunk | 2000 | - | - | - | N/A | - | - | N/A | Inconclusivo (ARBORIA Ausente) |

### 4.2 Comparação de LOD0 Idêntico: ARBORIA (LOD0 Forçado) vs. Melhor Godot Convencional
| Cenário | Instâncias | Melhor Godot Convencional | p95 Godot (ms) | p95 ARBORIA LOD0 (ms) | Razão p95 | VRAM Godot (MB) | VRAM ARBORIA LOD0 (MB) | Razão VRAM |
| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| dense_rock | 1 | MeshInstance3D | 1.24 | 1.85 | 1.50 | 111.7 | 130.2 | 1.17 |
| dense_rock | 500 | MeshInstance3D | 6.69 | 8.31 | 1.24 | 111.7 | 131.1 | 1.17 |

## 5. Diferenças de Qualidade Visual e Limitações Honestamente Registradas
1. **Sombras Dinâmicas no Cenário:** As variantes A e B nativas do Godot projetam e recebem sombras dinâmicas completas via Shadow Atlas. A variante ARBORIA escreve no buffer Forward+, mas ainda não injeta no passe de Shadow Map do Godot.
2. **Qualidade dos Materiais:** As variantes A e B utilizam o renderizador PBR completo do Godot (StandardMaterial3D). O ARBORIA utiliza um shader Cook-Torrance GGX procedural.
3. **Transições de LOD:** O ARBORIA executa seleção contínua de clusters Nanite DAG na GPU. Pequenos estalidos de pop geométrico podem ocorrer em distâncias limítrofes.
4. **Gargalo de Submissão em Escala:** A versão atual do ARBORIA faz 1 despacho de compute e 1 draw indirect por instância no loop C++. Para 2.000 instâncias, o tempo de CPU de submissão de comandos aumenta linearmente.

## 6. Decisão Formal GO / NO-GO
- **Critério Exigido:** Apresentar p95 de frame time $\le 67\%$ do melhor Godot convencional **OU** usar $\le 67\%$ da VRAM em pelo menos **2 combinações grandes** (instâncias $\ge 80$).
- **Combinações Grandes com Vantagem Validada:** 0 encontrada(s).

### **RESULTADO FINAL DA DECISÃO:** `NO-GO (Sem Vantagem Mensurável)`

> **Parecer Técnico:** O ARBORIA não apresentou vantagem de frame time ou VRAM dentro do limiar configurado nas combinações testadas.
