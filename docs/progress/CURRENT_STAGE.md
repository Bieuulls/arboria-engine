# ARBORIA ENGINE — STATUS DA ETAPA ATUAL

MISSÃO: CONCLUSÃO, REFINAMENTO E VALIDAÇÃO DO MOTOR GRÁFICO (ARBORIA ENGINE OFFICIAL)
ETAPA ATUAL: ETAPA 02 — SUBMISSÃO INDIRETA AGRUPADA REAL
ÚLTIMO GATE APROVADO: GATE 01 (PASSED)
COMMIT APROVADO: 3ea13d2
ARQUIVOS MODIFICADOS:
- native/renderer/scene/arboria_gpu_scene.h
- native/renderer/scene/arboria_gpu_scene.cpp
- native/renderer/scene/arboria_render_world.h
- native/renderer/scene/arboria_render_world.cpp
- native/renderer/integration/arboria_gdextension.cpp
- project/shaders/cull_clusters_global.glsl
- project/shaders/arboria_forward_raster_global.glsl
- project/scripts/arboria_native_pipeline.gd
- project/scripts/test_arboria_gpu_scene_global.gd
- project/scenes/test_arboria_gpu_scene_global.tscn
- tools/gates/run_gate.ps1
- artifacts/gates/stage_01/gate_result.json

FUNCIONALIDADES IMPLEMENTADAS:
- Ativação definitiva do GPU Scene Global como caminho principal de renderização no ARBORIA ENGINE.
- Geometria compartilhada entre todas as instâncias ativas (1 única alocação de malha na VRAM).
- Vinculação nativa C++ do método `render_scene_global` no `ArboriaNativeCore` (GDExtension), despachando o culling e o desenho indireto diretamente na GPU.
- Eliminação total do loop per-instance de dispatches e draws: O(1) submissões CPU/GPU.
- Suporte a escalas arbitrárias não uniformes e espelhadas (det < 0 ativa FLAG_MIRRORED bit 2 e inverte normais).
- Suporte a PBR completo no shader global (`arboria_forward_raster_global.glsl`), além dos modos Normal, Unshaded e Cluster Debug View.
- Mapeamento acelerado O(1) de threads GPU em batches uniformes no `cull_clusters_global.glsl`.

TESTES EXECUTADOS:
- `build_native.ps1`: 18/18 testes unitários nativos C++ aprovados (100% OK).
- `test_arboria_gpu_scene_global.tscn` executado em hardware físico real NVIDIA GeForce RTX 3050 (Godot 4.7.2 Forward+ Vulkan 1.4).
- Validação mandante dos 4 patamares de instâncias:
  * Tier 1 (1 instância): 367 clusters avaliados, 23 visíveis, 1.956 triângulos, 1 dispatch, 1 draw indirect.
  * Tier 2 (80 instâncias): 29.360 clusters avaliados, 1.364 visíveis, 115.468 triângulos, 1 dispatch, 1 draw indirect.
  * Tier 3 (500 instâncias): 183.500 clusters avaliados, 5.641 visíveis, 475.651 triângulos, 1 dispatch, 1 draw indirect.
  * Tier 4 (2.000 instâncias): 734.000 clusters avaliados, 12.090 visíveis, 993.912 triângulos, 1 dispatch, 1 draw indirect.
- `tools/gates/run_gate.ps1 -Stage 01`: APROVADO (Build: PASSED, Runtime: PASSED, Geometry: PASSED, GPU: PASSED, Regressions: PASSED, 0 erros, 0 crashes, 0 RIDs vazados).

RESULTADOS:
- Escalonamento comprovado de 1 a 2.000 instâncias com custo de submissão rigorosamente constante (1 dispatch, 1 draw).
- Zero erros de validação Vulkan ou drivers.
- GATE 01 formalmente aprovado com evidências reproduzíveis.

EVIDÊNCIAS:
- `artifacts/gates/stage_01/gate_result.json`
- `artifacts/gates/stage_01/godot_run.log`
- `artifacts/gates/stage_01/diag_arboria_gpu_scene_global.png`
- `project/diag_arboria_gpu_scene_global.png`

PROBLEMAS RESTANTES:
- Nenhum no Gate 01.

PRÓXIMA AÇÃO EXECUTÁVEL:
- Executar ETAPA 02: Refinar a submissão indireta agrupada, buffers com layouts estritos multidraw/indirect commands, otimização de barreiras Vulkan entre compute e raster e benchmarking de custo de submissão CPU/GPU.
