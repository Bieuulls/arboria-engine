# RELATÓRIO 01 — DIAGNÓSTICO INICIAL DO PIPELINE ARBORIA
**Data de Execução:** 21 de Outubro de 2026  
**Repositório Alvo:** `D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL`  
**Commit de Referência Baseline:** `c244587` (Git inicializado e congelado para auditoria)

---

## 1. AMBIENTE DE EXECUÇÃO DETECTADO DINAMICAMENTE

Os seguintes dados foram consultados diretamente do ambiente local (sem valores fixos no código):
- **Sistema Operacional:** Windows 10 Pro (10.0.19045 AMD64)
- **Godot Engine:** `Godot Engine v4.7.2.stable.official.ed1daf0bf`
- **Renderizador Primário:** Vulkan 1.4.351 — Forward+ Clustered
- **GPU Detectada pelo Driver:** NVIDIA GeForce RTX 3050 Laptop GPU (Driver NVIDIA 556.12)
- **Compilador C++:** MSVC 19.43.34808.0 (Visual Studio 2022 Release x64) / CMake 3.31.6
- **Python de Testes:** Python 3.12.10 (MSC v.1943 64-bit)

---

## 2. INVENTÁRIO OBRIGATÓRIO DE ARQUIVOS (HASHES SHA-256)

| Arquivo | Tamanho | Hash SHA-256 |
| :--- | :---: | :--- |
| `project/scripts/vg_gpu_pipeline.gd` | 19.528 B | `e30739841e57d49dfe6ec593022b40b873e58f102fcca128210f52ba41285103` |
| `project/scripts/main_viewer.gd` | 12.740 B | `0624adf7b71933392c339b390a779b8b8f9340a0a8898f7d96258bb7e4e31781` |
| `project/scripts/test_fase3_pipeline.gd` | 5.740 B | `6e9c3c2d37f5d62b4ed51b02205dc1d1464df769b9c3982dbe0943db8e359134` |
| `project/scripts/test_visual_validation.gd` | 8.728 B | `116726a28286c5a0cd31bae4155024c3623add89425c6e333f7ac70fd664d584` |
| `project/scripts/benchmark_fase3.gd` | 7.706 B | `5af88895a109221d8b7bed480e919603574c8490224b600a829cdb7cef23cfef` |
| `project/shaders/cull_clusters.glsl` | 6.330 B | `eaacd5670214990472751b44fb293621ff733fa683e4fe58af5e92262af24301` |
| `project/shaders/vg_cluster_render.gdshader` | 2.808 B | `9d6434aed6e346b1db5b340f12ef4a8b9ff15ad5f9ad7de477c6174ab850ca11` |
| `tools/baker/src/vg_baker_main.cpp` | 36.757 B | `be97f330bb7c1941c84b780304162c41697bc8b92066d6df9ac214fce8ca6c8b` |
| `tests/test_suite.py` | 8.424 B | `84a84e4d8499b5635713addc89bdada3e8e13b9caf7cfbdaefd289eec6ee5ea1` |

---

## 3. DIAGNÓSTICO DOS DEFEITOS COMPROVADOS

### Defeito 1 (P0): Desenho Indireto Desconectado da Renderização Principal da Cena
- **Localização:** `project/scripts/vg_gpu_pipeline.gd` (linhas 320–337) e `project/scripts/main_viewer.gd` (linhas 174–185).
- **Problema Real:** 
  O visualizador principal utiliza `MultiMeshInstance3D` com `multimesh.instance_count = total_clusters`. Quando os clusters são descartados na GPU pelo compute shader, a renderização convencional continua enviando 367 instâncias à GPU via Forward+, e o Vertex Shader apenas colapsa os vértices com `VERTEX = vec3(0.0)`.
- **Invalidação do Teste Anterior:** Em `test_fase3_pipeline.gd`, a função `execute_indirect_draw()` utilizava um triângulo procedural isolado (`gl_VertexIndex % 3`) desenhado em um framebuffer de diagnóstico `64x64`. Esse teste comprovou apenas que a chamada Vulkan `draw_list_draw_indirect` funciona em um framebuffer offscreen isolado, mas **NÃO comprovou** que a geometria real do `.vgmesh` é desenhada por esse caminho nem que a cena do Godot consome esse resultado.

### Defeito 2 (P0): Métricas Artificiais e Anomalia de 3 FPS no Benchmark
- **Localização:** `project/scripts/benchmark_fase3.gd` (linhas 170–195).
- **Problema Real:** 
  Foram identificadas multiplicações sintéticas como:
  ```gdscript
  gpu_time_ms = avg_frame_time * 0.45
  gpu_time_ms = avg_frame_time * 0.35
  gpu_time_ms = max(0.04, st["gpu_time_us"] / 1000.0)
  cpu_sub_ms = 0.02
  ```
  Essas linhas falsificam as medições gráficas e serão imediatamente expurgadas.
- **Anomalia de 3 FPS:** O cenário A (malha original com 15.800 triângulos) registrou 3 FPS. Em uma RTX 3050, 15.800 triângulos deveriam rodar a centenas de FPS. A causa deve ser isolada (ex: recriação síncrona ou compilação contínua de pipelines, ausência de swap de buffers, etc.).

### Defeito 3 (P1): Validação Visual Restrita à Ocupação de Silhueta (Alpha)
- **Localização:** `project/scripts/test_visual_validation.gd`.
- **Problema Real:** 
  O teste comparava apenas `c_ref.a > 0.1` vs `c_gpu.a > 0.1`. Uma máscara preta opaca teria 100% de alpha sem nenhuma fidelidade geométrica ou de cor. É imperativo testar correspondência RGB em modo unshaded e modo lit PBR com métricas rígidas de MSE/PSNR/SSIM ou diferença RGB pixel a pixel.

### Defeito 4 (P1): Verificação do Baker Limitada a Contagem de Triângulos
- **Localização:** `tools/baker/src/vg_baker_main.cpp` (linhas 555–562).
- **Problema Real:** 
  A validação `lod0_lossless = (lods[0].triangle_count == (original_indices.size() / 3))` comparava apenas quantidade inteira de triângulos, ignorando posições exatas dos vértices, normais, coordenadas de textura UV, e conectividade topológica.

---

## 4. PLANO DE AÇÃO SISTEMÁTICO

1. **Investigar Anomalia de 3 FPS e Eliminar Métricas Fictícias:** Reestruturar `benchmark_fase3.gd` com medições 100% puras (tempo de frame real, tempo CPU medido, queries GPU reais; marcar `NÃO MEDIDO` onde a API não fornecer leitura).
2. **Conectar Desenho Indireto Real com Geometria `.vgmesh`:** Integrar pipeline de desenho indireto que consuma os buffers de vértices e índices reais do modelo e validar os 5 testes negativos (A, B, C, D, E). Avaliar a fronteira de integração entre `RenderingDevice` e o scene tree Forward+ do Godot.
3. **Auditar Validação Visual Pixel a Pixel (RGB & Shading):** Comparar imagens renderizadas em RGB com materiais idênticos, detectando superfícies pretas anômalas e junções entre clusters.
4. **Verificador C++ Geométrico Verdadeiro no Baker:** Implementar comparação profunda de atributos e matrizes de triângulos no LOD 0 contra a entrada original OBJ normalizada.
