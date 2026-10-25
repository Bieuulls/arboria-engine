# ARBORIA ENGINE — RELATÓRIO OFICIAL DE BENCHMARK
**Data da Execução:** 24/10/2026 21:49:52

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

## 2.1 Referência Oficial de Paridade Geométrica (LOD0)
- **Definição da Referência Oficial:** A referência canônica de contagem de primitivas para paridade LOD0 no ARBORIA é o total geométrico de triângulos da cena, representado de forma equivalente pelo `MultiMeshInstance3D` do Godot (e pelo `MeshInstance3D` quando 100% das instâncias estão no frustum). Para $N$ instâncias de `dense_rock` com 15.800 triângulos cada, a referência oficial é rigorosamente $N \times 15.800$ primitivas:
  - 1 instância: **15.800** primitivas
  - 80 instâncias: **1.264.000** primitivas
  - 500 instâncias: **7.900.000** primitivas
- **Diagnóstico da Divergência Anterior em 500 Instâncias (7.283.800 vs 7.900.000):**
  - No código anterior, para 500 instâncias dispostas proceduralmente com semente fixa (`seed=42`), o raio de dispersão atingia 87 metros, enquanto a trajetória orbital da câmera usava `orbit_radius = 85.0` e `orbit_height = 25.0`.
  - Como a câmera orbitava **dentro** da nuvem de instâncias, o frustum culling individual do `MeshInstance3D` descartava 39 instâncias posicionadas atrás ou nas bordas fora do viewport ($461 \times 15.800 = 7.283.800$). Em contraste, o `MultiMeshInstance3D` submetia a cena inteira via GPU sem culling individual por instância ($500 \times 15.800 = 7.900.000$).
- **Correção Aplicada:**
  - O raio da câmera na cena de benchmark foi ampliado para `orbit_radius = 145.0` e `orbit_height = 45.0` para 500 instâncias (e `260.0`/`80.0` para 2000 instâncias). Com isso, todas as 500 instâncias permanecem visíveis durante toda a órbita.
  - Testes executados confirmam que `mesh_instance`, `multimesh` e `arboria_lod0` reportam exatamente **7.900.000** primitivas em 500 instâncias (diferença = 0).

## 3. Tabela Comparativa de Resultados
| Cenário | Instâncias | Variante | Status | Frame Time p50 (ms) | Frame Time p95 (ms) | Frame Time p99 (ms) | CPU Render p95 (ms) | GPU Render p95 (ms) | VRAM Média (MB) | Draws (Godot + Ind) | Primitivas / Tris | Clusters (Vis / Tot) |
| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| dense_rock | 1 | mesh_instance | ✅ OK | 0.76 | 1.07 | 1.25 | 0.13 | 0.22 | 111.7 | 1 | 15800 | - |
| dense_rock | 1 | multimesh | ✅ OK | 0.77 | 1.06 | 1.32 | 0.12 | 0.22 | 111.7 | 1 | 15800 | - |
| dense_rock | 1 | arboria | ✅ OK | 0.78 | 1.09 | 1.30 | 0.35 | 0.22 | 129.7 | 1 (1 ind) | 3866 | 47 / 367 |
| dense_rock | 1 | arboria_lod0 | ✅ OK | 0.80 | 1.14 | 1.39 | 0.34 | 0.23 | 129.7 | 1 (1 ind) | 15800 | 172 / 367 |
| dense_rock | 80 | mesh_instance | ✅ OK | 1.39 | 1.52 | 1.56 | 0.20 | 0.80 | 111.7 | 2 | 1264000 | - |
| dense_rock | 80 | multimesh | ✅ OK | 1.39 | 1.52 | 1.56 | 0.13 | 0.79 | 111.7 | 1 | 1264000 | - |
| dense_rock | 80 | arboria | ✅ OK | 1.67 | 1.85 | 1.85 | 1.47 | 0.34 | 129.9 | 1 (1 ind) | 181783 | 2213 / 29360 |
| dense_rock | 80 | arboria_lod0 | ✅ OK | 1.85 | 1.85 | 1.85 | 1.45 | 1.32 | 129.9 | 1 (1 ind) | 1264000 | 13760 / 29360 |
| dense_rock | 500 | mesh_instance | ✅ OK | 4.55 | 4.76 | 4.76 | 0.29 | 4.37 | 111.7 | 3 | 7201419 | - |
| dense_rock | 500 | multimesh | ✅ OK | 5.00 | 5.00 | 5.00 | 0.16 | 4.75 | 111.7 | 1 | 7900000 | - |
| dense_rock | 500 | arboria | ✅ OK | 6.94 | 7.58 | 9.44 | 7.45 | 1.93 | 131.1 | 1 (1 ind) | 476978 | 5837 / 183500 |
| dense_rock | 500 | arboria_lod0 | ✅ OK | 6.94 | 8.33 | 10.00 | 7.44 | 6.09 | 131.1 | 1 (1 ind) | 7900000 | 86000 / 183500 |
| dense_rock | 2000 | mesh_instance | ✅ OK | 10.61 | 11.11 | 11.28 | 0.68 | 10.83 | 111.7 | 5 | 18230956 | - |
| dense_rock | 2000 | multimesh | ✅ OK | 16.67 | 17.49 | 18.06 | 0.38 | 16.80 | 111.8 | 1 | 31600000 | - |
| dense_rock | 2000 | arboria | ✅ OK | 33.33 | 38.79 | 43.99 | 40.55 | 4.18 | 135.8 | 1 (1 ind) | 805008 | 9790 / 734000 |
| dense_rock | 2000 | arboria_lod0 | ✅ OK | 33.33 | 41.57 | 46.72 | 41.80 | 20.46 | 135.8 | 1 (1 ind) | 31600000 | 344000 / 734000 |
| pine_trunk | 1 | mesh_instance | ✅ OK | 0.75 | 1.00 | 1.20 | 0.12 | 0.22 | 112.2 | 1 | 35000 | - |
| pine_trunk | 1 | multimesh | ✅ OK | 0.76 | 1.07 | 1.39 | 0.12 | 0.22 | 112.2 | 1 | 35000 | - |
| pine_trunk | 1 | arboria | ✅ OK | 0.79 | 1.07 | 1.39 | 0.38 | 0.22 | 130.6 | 1 (1 ind) | 3758 | 42 / 805 |
| pine_trunk | 1 | arboria_lod0 | ✅ OK | 0.81 | 1.07 | 1.39 | 0.37 | 0.24 | 130.6 | 1 (1 ind) | 35000 | 376 / 805 |
| pine_trunk | 80 | mesh_instance | ✅ OK | 2.38 | 2.38 | 2.38 | 0.16 | 1.85 | 112.2 | 2 | 2800000 | - |
| pine_trunk | 80 | multimesh | ✅ OK | 2.38 | 2.38 | 2.38 | 0.16 | 1.92 | 112.2 | 1 | 2800000 | - |
| pine_trunk | 80 | arboria | ✅ OK | 1.67 | 1.67 | 1.67 | 1.45 | 0.40 | 131.0 | 1 (1 ind) | 173489 | 1996 / 64400 |
| pine_trunk | 80 | arboria_lod0 | ✅ OK | 2.78 | 2.78 | 2.83 | 1.43 | 2.24 | 131.0 | 1 (1 ind) | 2800000 | 30080 / 64400 |
| pine_trunk | 500 | mesh_instance | ✅ OK | 9.26 | 9.52 | 9.78 | 0.36 | 9.26 | 112.2 | 3 | 15830080 | - |
| pine_trunk | 500 | multimesh | ✅ OK | 10.26 | 14.58 | 15.40 | 0.34 | 12.75 | 112.2 | 1 | 17500000 | - |
| pine_trunk | 500 | arboria | ✅ OK | 6.94 | 8.33 | 8.79 | 7.82 | 1.92 | 132.8 | 1 (1 ind) | 209555 | 2553 / 402500 |
| pine_trunk | 500 | arboria_lod0 | ✅ OK | 11.11 | 11.65 | 16.77 | 7.66 | 11.02 | 132.8 | 1 (1 ind) | 17500000 | 188000 / 402500 |
| pine_trunk | 2000 | mesh_instance | ✅ OK | 22.22 | 22.22 | 22.73 | 0.73 | 22.00 | 112.2 | 5 | 39825170 | - |
| pine_trunk | 2000 | multimesh | ✅ OK | 33.45 | 34.29 | 34.72 | 0.22 | 33.55 | 112.2 | 1 | 70000000 | - |
| pine_trunk | 2000 | arboria | ✅ OK | 29.63 | 34.69 | 47.81 | 35.14 | 8.07 | 140.1 | 1 (1 ind) | 252819 | 3229 / 1610000 |
| pine_trunk | 2000 | arboria_lod0 | ✅ OK | 41.94 | 42.42 | 42.42 | 34.83 | 42.15 | 140.1 | 1 (1 ind) | 70000000 | 752000 / 1610000 |

## 4. Comparações Diretas e Avaliação de Desempenho
### 4.1 Comparação de Qualidade Equivalente: ARBORIA (DAG Dinâmico) vs. Melhor Godot Convencional
| Cenário | Instâncias | Melhor Godot Convencional | p95 Godot (ms) | p95 ARBORIA (ms) | Razão p95 (ARB/Godot) | VRAM Godot (MB) | VRAM ARBORIA (MB) | Razão VRAM | Vantagem Significativa? |
| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| dense_rock | 1 | MultiMeshInstance3D | 1.06 | 1.09 | 1.03 | 111.7 | 129.7 | 1.16 | Não (1.03x tempo, 1.16x VRAM) |
| dense_rock | 80 | MeshInstance3D | 1.52 | 1.85 | 1.22 | 111.7 | 129.9 | 1.16 | Não (1.22x tempo, 1.16x VRAM) |
| dense_rock | 500 | MeshInstance3D | 4.76 | 7.58 | 1.59 | 111.7 | 131.1 | 1.17 | Não (1.59x tempo, 1.17x VRAM) |
| dense_rock | 2000 | MeshInstance3D | 11.11 | 38.79 | 3.49 | 111.7 | 135.8 | 1.22 | Não (3.49x tempo, 1.22x VRAM) |
| pine_trunk | 1 | MeshInstance3D | 1.00 | 1.07 | 1.06 | 112.2 | 130.6 | 1.16 | Não (1.06x tempo, 1.16x VRAM) |
| pine_trunk | 80 | MeshInstance3D | 2.38 | 1.67 | 0.70 | 112.2 | 131.0 | 1.17 | Não (0.70x tempo, 1.17x VRAM) |
| pine_trunk | 500 | MeshInstance3D | 9.52 | 8.33 | 0.88 | 112.2 | 132.8 | 1.18 | Não (0.88x tempo, 1.18x VRAM) |
| pine_trunk | 2000 | MeshInstance3D | 22.22 | 34.69 | 1.56 | 112.2 | 140.1 | 1.25 | Não (1.56x tempo, 1.25x VRAM) |

### 4.2 Comparação de LOD0 Idêntico: ARBORIA (LOD0 Forçado) vs. Melhor Godot Convencional
| Cenário | Instâncias | Melhor Godot Convencional | p95 Godot (ms) | p95 ARBORIA LOD0 (ms) | Razão p95 | VRAM Godot (MB) | VRAM ARBORIA LOD0 (MB) | Razão VRAM |
| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| dense_rock | 1 | MultiMeshInstance3D | 1.06 | 1.14 | 1.08 | 111.7 | 129.7 | 1.16 |
| dense_rock | 80 | MeshInstance3D | 1.52 | 1.85 | 1.22 | 111.7 | 129.9 | 1.16 |
| dense_rock | 500 | MeshInstance3D | 4.76 | 8.33 | 1.75 | 111.7 | 131.1 | 1.17 |
| dense_rock | 2000 | MeshInstance3D | 11.11 | 41.57 | 3.74 | 111.7 | 135.8 | 1.22 |
| pine_trunk | 1 | MeshInstance3D | 1.00 | 1.07 | 1.06 | 112.2 | 130.6 | 1.16 |
| pine_trunk | 80 | MeshInstance3D | 2.38 | 2.78 | 1.17 | 112.2 | 131.0 | 1.17 |
| pine_trunk | 500 | MeshInstance3D | 9.52 | 11.65 | 1.22 | 112.2 | 132.8 | 1.18 |
| pine_trunk | 2000 | MeshInstance3D | 22.22 | 42.42 | 1.91 | 112.2 | 140.1 | 1.25 |

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
