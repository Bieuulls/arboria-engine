# RELATÓRIO 04 — BENCHMARK REAL E METODOLOGIA RIGOROSA
**Data:** 21 de Outubro de 2026  
**Diretório:** `D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL`  
**Responsável:** Engenheiro de Renderização (ARBORIA ENGINE Core)

---

## 1. INVESTIGAÇÃO DA ANOMALIA DE 3 FPS DO RELATÓRIO ANTERIOR

No relatório de benchmark anterior, constava um resultado aberrante:
- **Godot Convencional (Cenário A):** 3 FPS com 15.800 triângulos.
- **ARBORIA GPU (Cenário D):** 60 FPS.

Essa disparidade é fisicamente inconsistente para uma GPU NVIDIA GeForce RTX 3050 rasterizando apenas 15.800 triângulos.

### Causa Raiz Descoberta
1. Na implementação anterior de `benchmark_fase3.gd`, a variável `gpu_mesh_instance` recebia `pipeline.multimesh_instance`.
2. O método `pipeline.load_vgmesh(vg_data)` era chamado, mas `pipeline.setup_multimesh(vg_data)` **não era executado**.
3. Como consequência, `pipeline.multimesh_instance` permanecia como `Nil`.
4. No loop `run_scenario_loop()`, a cada frame o motor executava:
   `gpu_mesh_instance.visible = (current_scenario >= 2)`
5. Essa instrução disparava uma exceção crítica em GDScript (`Invalid assignment of property or key 'visible' on Nil`) **em todos os frames**.
6. O terminal do Godot e o buffer de stdout eram inundados por dezenas de milhares de stack traces por segundo. A sobrecarga de I/O de texto no console travou o thread principal da CPU, derrubando o framerate de todos os cenários para 3 FPS.
7. O desenvolvedor anterior, ao invés de corrigir a inicialização, inseriu fórmulas sintéticas como `gpu_time_ms = avg_frame_time * 0.45` e mascarou as medições com constantes fictícias.

### Correção Aplicada
O pipeline foi corrigido chamando `pipeline.setup_multimesh(vg_data)`. Com a eliminação dos erros de console, o Godot convencional e o ARBORIA executam em sua velocidade real nativa sem nenhum gargalo de CPU induzido por logs.

---

## 2. METODOLOGIA DE BENCHMARK APLICADA

- **Resolução de Tela:** 1920 × 1080 (Full HD).
- **Driver Gráfico:** Vulkan 1.4.351 Forward+ (NVIDIA RTX 3050 Laptop GPU).
- **Câmera:** Posição `(10.0, 4.0, 14.0)`, Olhando para `(0, 0, 0)`, FOV 70°, Near 0.05, Far 500.0.
- **Iluminação:** `DirectionalLight3D` com rotação `(-0.7, 0.5, 0.0)`.
- **Material de Diagnóstico:** PBR StandardMaterial3D (Albedo `Color(0.8, 0.82, 0.85)`, Roughness 0.5, Metallic 0.05).
- **Controle de VSync:** `Engine.max_fps = 0` (taxa de atualização destravada para medir capacidade máxima do pipeline).
- **Período de Aquecimento (Warmup):** **120 frames por cenário**, permitindo estabilização de compilação de shaders Vulkan, alocações de heaps e clocks da GPU.
- **Período de Amostragem:** **300 frames contínuos por cenário** (totalizando 1.200 amostras medidas).
- **Métricas Estatísticas:** Cálculo de **Mediana** e **Percentil 95 (P95)** dos tempos de frame reais, registrados individualmente via `Time.get_ticks_usec()`.

---

## 3. RESULTADOS COMPARATIVOS (1.200 FRAMES MEDIDOS)

| Cenário | Descrição da Geometria | Triângulos | FPS Efetivo | Frame Mediana | Frame P95 | CPU Submit | GPU Compute Culling | GPU Raster Pass | VRAM Nominal |
|---|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **A** | Godot Convencional (Malha Base) | 15.800 | **59.9** | **16.71 ms** | **17.46 ms** | 0.000 ms | *NÃO SE APLICA* | *NÃO MEDIDO* | 1.481 KB |
| **B** | Godot Convencional (LOD 3 Equivalente) | 1.968 | **59.9** | **16.69 ms** | **17.89 ms** | 0.000 ms | *NÃO SE APLICA* | *NÃO MEDIDO* | 184 KB |
| **C** | ARBORIA GPU (Raw LOD 0 sem Culling) | 15.800 | **59.9** | **16.70 ms** | **17.46 ms** | 0.072 ms | 0.005 ms | *NÃO MEDIDO* | 1.693 KB |
| **D** | ARBORIA GPU (Culling & DAG Ativados) | 12.962 | **59.8** | **16.72 ms** | **18.06 ms** | 0.085 ms | 0.029 ms | *NÃO MEDIDO* | 1.693 KB |

---

## 4. ANÁLISE TÉCNICA E LIMITAÇÕES DE MEDIÇÃO

1. **Tempo de Frame Total e FPS:**
   Tanto o Godot convencional quanto o ARBORIA operam na faixa de 16.7 ms (~60 FPS) sob a janela de exibição do Windows devido à sincronização com o Compositor DWM do sistema operacional.
2. **Tempo CPU de Preparação e Submissão:**
   A sobrecarga de submissão do ARBORIA na CPU para o despacho do Compute Shader é de apenas **0.085 ms** (85 microssegundos). Trata-se de uma submissão extremamente leve que não bloqueia o thread principal.
3. **Tempo de GPU Compute Culling:**
   O tempo real do shader `cull_clusters.glsl` medido através de queries assíncronas do Vulkan é de **0.029 ms** (29 microssegundos) para avaliar os 367 clusters e selecionar as instâncias ativas.
4. **Tempo de Rasterização e Cena Completa:**
   Declarado explicitamente como **NÃO MEDIDO**. A API padrão Forward+ do Godot 4 não expõe timestamps isolados de DrawPass do renderizador sem ferramentas externas de instrumentação (como RenderDoc ou NVIDIA Nsight Graphics). Apresentar o tempo do Compute Shader como se fosse o tempo GPU total é incorreto e foi estritamente evitado.
5. **Memória de Vídeo (VRAM):**
   - VRAM nominal alocada calculada: **1.693 KB** (buffers compactados de geometria, metadados e seleção).
   - Consumo real de heap do driver: **NÃO MEDIDO** (requer profiling externo a nível de driver Vulkan).

---

## 5. DADOS BRUTOS

Todas as 1.200 amostras individuais de frame time, tempo de submissão de CPU e FPS frame a frame foram salvas no arquivo CSV:
`D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL\AUDITORIA_FASE3_FINAL\benchmark_raw_data.csv`
