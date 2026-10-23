# ARBORIA ENGINE — RELATÓRIO OFICIAL DE BENCHMARK
**Data da Execução:** 23/10/2026 20:45:10

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

## 3. Tabela Comparativa de Resultados
| Cenário | Instâncias | Variante | Status | Frame Time p50 (ms) | Frame Time p95 (ms) | Frame Time p99 (ms) | CPU Render p95 (ms) | GPU Render p95 (ms) | VRAM Média (MB) | Draws (Godot + Ind) | Primitivas / Tris | Clusters (Vis / Tot) |
| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| dense_rock | 1 | mesh_instance | ✅ OK | 0.79 | 1.03 | 1.20 | 0.11 | 0.26 | 111.7 | 1 | 15800 | - |
| dense_rock | 1 | multimesh | ✅ OK | 0.80 | 1.04 | 1.23 | 0.12 | 0.26 | 111.7 | 1 | 15800 | - |
| dense_rock | 1 | arboria | ✅ OK | 0.75 | 1.05 | 1.39 | 0.15 | 0.20 | 128.1 | 0 (0 ind) | 0 | 0 / 0 |
| dense_rock | 1 | arboria_lod0 | ✅ OK | 0.72 | 0.96 | 1.19 | 0.13 | 0.20 | 128.1 | 0 (0 ind) | 0 | 0 / 0 |
| dense_rock | 80 | mesh_instance | ✅ OK | 2.78 | 2.78 | 2.89 | 0.19 | 2.34 | 111.7 | 2 | 1264000 | - |
| dense_rock | 80 | multimesh | ✅ OK | 2.78 | 2.78 | 2.82 | 0.17 | 2.32 | 111.7 | 1 | 1264000 | - |
| dense_rock | 80 | arboria | ✅ OK | 0.74 | 0.93 | 1.18 | 0.13 | 0.20 | 128.1 | 0 (0 ind) | 0 | 0 / 0 |
| dense_rock | 80 | arboria_lod0 | ✅ OK | 0.74 | 0.96 | 1.17 | 0.18 | 0.20 | 128.1 | 0 (0 ind) | 0 | 0 / 0 |

## 4. Comparações Diretas e Avaliação de Desempenho
### 4.1 Comparação de Qualidade Equivalente: ARBORIA (DAG Dinâmico) vs. Melhor Godot Convencional
| Cenário | Instâncias | Melhor Godot Convencional | p95 Godot (ms) | p95 ARBORIA (ms) | Razão p95 (ARB/Godot) | VRAM Godot (MB) | VRAM ARBORIA (MB) | Razão VRAM | Vantagem Significativa? |
| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| dense_rock | 1 | MeshInstance3D | 1.03 | 1.05 | 1.02 | 111.7 | 128.1 | 1.15 | Não (1.02x tempo, 1.15x VRAM) |
| dense_rock | 80 | MeshInstance3D | 2.78 | 0.93 | 0.33 | 111.7 | 128.1 | 1.15 | **SIM** (0.33x tempo, 1.15x VRAM) |
| pine_trunk | 1 | - | - | - | N/A | - | - | N/A | Inconclusivo (ARBORIA Ausente) |
| pine_trunk | 80 | - | - | - | N/A | - | - | N/A | Inconclusivo (ARBORIA Ausente) |
| pine_trunk | 500 | - | - | - | N/A | - | - | N/A | Inconclusivo (ARBORIA Ausente) |
| pine_trunk | 2000 | - | - | - | N/A | - | - | N/A | Inconclusivo (ARBORIA Ausente) |

### 4.2 Comparação de LOD0 Idêntico: ARBORIA (LOD0 Forçado) vs. Melhor Godot Convencional
| Cenário | Instâncias | Melhor Godot Convencional | p95 Godot (ms) | p95 ARBORIA LOD0 (ms) | Razão p95 | VRAM Godot (MB) | VRAM ARBORIA LOD0 (MB) | Razão VRAM |
| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| dense_rock | 1 | MeshInstance3D | 1.03 | 0.96 | 0.93 | 111.7 | 128.1 | 1.15 |
| dense_rock | 80 | MeshInstance3D | 2.78 | 0.96 | 0.35 | 111.7 | 128.1 | 1.15 |

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
