# ARBORIA ENGINE — AGENT TASK BOARD

Formato: TASK_ID | AGENTE | ARQUIVOS | STATUS | DEPENDÊNCIAS | ÚLTIMA ALTERAÇÃO | REVISOR

---

## Wave 1 — Em paralelo (P0 CRÍTICA)

### Geometry Agent
| TASK_ID | AGENTE | ARQUIVOS | STATUS | DEPENDÊNCIAS | ÚLTIMA ALTERAÇÃO | REVISOR |
|---------|--------|----------|--------|--------------|------------------|---------|
| GEOMETRY-001 | Geometry Agent | native/renderer/core/arboria_geometric_compiler.cpp | concluído | Nenhuma | — | QA Agent |
| GEOMETRY-002 | Geometry Agent | native/renderer/core/arboria_geometric_compiler.cpp | concluído | GEOMETRY-001 | — | QA Agent |
| GEOMETRY-003 | Geometry Agent | native/renderer/core/arboria_geometric_compiler.cpp | concluído | GEOMETRY-001 | — | QA Agent |
| GEOMETRY-004 | Geometry Agent | native/renderer/core/arboria_geometric_compiler.cpp | concluído | GEOMETRY-001 | — | QA Agent |
| GEOMETRY-005 | Geometry Agent | native/renderer/core/arboria_geometric_compiler.cpp | concluído | GEOMETRY-001 | — | QA Agent |
| GEOMETRY-006 | Geometry Agent | native/renderer/core/arboria_geometric_compiler.cpp | concluído | GEOMETRY-001 | — | QA Agent |

### Godot Agent
| TASK_ID | AGENTE | ARQUIVOS | STATUS | DEPENDÊNCIAS | ÚLTIMA ALTERAÇÃO | REVISOR |
|---------|--------|----------|--------|--------------|------------------|---------|
| GODOT-001 | Godot Agent | addons/arboria/editor/arboria_mesh_import_plugin.gd, addons/arboria/core/arboria_asset_importer.gd | concluído | Nenhuma | — | QA Agent |
| GODOT-002 | Godot Agent | addons/arboria/core/arboria_asset_importer.gd, native/renderer/core/arboria_geometric_compiler.cpp | concluído | GEOMETRY-001 | — | Geometry Agent |
| GODOT-003 | Godot Agent | addons/arboria/arboria_plugin.gd, native/renderer/integration/arboria_gdextension.cpp | concluído | Nenhuma | — | QA Agent |
| GODOT-004 | Godot Agent | project/scripts/*, project/scenes/* | concluído | GODOT-003 | — | GPU Agent |
| GODOT-005 | Godot Agent | project/scripts/arboria_asset_importer.gd, assets/* | concluído | GODOT-001 | — | QA Agent |
| GODOT-006 | Godot Agent | addons/arboria/*, project/scripts/* | concluído | GODOT-001 | — | QA Agent |

### C++ Core Agent
| TASK_ID | AGENTE | ARQUIVOS | STATUS | DEPENDÊNCIAS | ÚLTIMA ALTERAÇÃO | REVISOR |
|---------|--------|----------|--------|--------------|------------------|---------|
| CORE-001 | C++ Core Agent | native/renderer/core/arboria_runtime.cpp/h | concluído | Nenhuma | — | QA Agent |
| CORE-002 | C++ Core Agent | native/renderer/scene/arboria_mesh_registry.cpp/h | concluído | Nenhuma | — | QA Agent |
| CORE-003 | C++ Core Agent | native/renderer/scene/arboria_instance_registry.cpp/h | concluído | Nenhuma | — | QA Agent |
| CORE-004 | C++ Core Agent | native/renderer/integration/arboria_scene_bridge.cpp/h | concluído | CORE-002, CORE-003 | — | GPU Agent |
| CORE-005 | C++ CoreAgent | native/renderer/core/*, native/renderer/scene/* | concluído | CORE-001, CORE-002 | — | QA Agent |
| CORE-006 | C++ Core Agent | native/renderer/core/arboria_geometric_compiler.cpp, native/renderer/build_native.bat | concluído | GEOMETRY-001 | — | Geometry Agent |
| CORE-007 | C++ Core Agent | native/renderer/tests/test_native_core.cpp, native/renderer/tests/test_arboria_advanced.cpp | concluído | CORE-001 | — | QA Agent |

### GPU Agent
| TASK_ID | AGENTE | ARQUIVOS | STATUS | DEPENDÊNCIAS | ÚLTIMA ALTERAÇÃO | REVISOR |
|---------|--------|----------|--------|--------------|------------------|---------|
| GPU-001 | GPU Agent | native/renderer/gpu/*, project/shaders/* | concluído | Nenhuma | — | C++ Core Agent |
| GPU-002 | GPU Agent | project/shaders/cull_clusters_v2.glsl, project/shaders/raster_clusters_v2.glsl | concluído | Nenhuma | — | C++ Core Agent |
| GPU-003 | GPU Agent | native/renderer/scene/arboria_gpu_scene.cpp/h | concluído | CORE-004 | — | C++ Core Agent |
| GPU-004 | GPU Agent | project/shaders/cull_clusters_v2.glsl, native/renderer/scene/arboria_visibility_manager.cpp | concluído | GPU-001 | — | QA Agent |
| GPU-005 | GPU Agent | native/renderer/scene/arboria_gpu_scene.cpp, native/renderer/core/arboria_geometric_compiler.cpp | concluído | GEOMETRY-005 | — | Geometry Agent |
| GPU-006 | GPU Agent | native/renderer/scene/arboria_streaming_manager.cpp/h | concluído | CORE-002 | — | QA Agent |
| GPU-007 | GPU Agent | native/renderer/scene/arboria_gpu_scene.cpp | concluído | GPU-001 | — | QA Agent |
| GPU-008 | GPU Agent | native/renderer/gpu/arboria_indirect_renderer.cpp, project/shaders/arboria_forward_raster.glsl | concluído | GPU-001 | — | Godot Agent |

### QA Agent
| TASK_ID | AGENTE | ARQUIVOS | STATUS | DEPENDÊNCIAS | ÚLTIMA ALTERAÇÃO | REVISOR |
|---------|--------|----------|--------|--------------|------------------|---------|
| QA-001 | QA Agent | native/renderer/tests/* | concluído | Nenhuma | — | Claude Coordenador |
| QA-002 | QA Agent | native/renderer/core/arboria_geometric_compiler.cpp | concluído | GEOMETRY-001 | — | Claude Coordenador |
| QA-003 | QA Agent | native/renderer/* | concluído | CORE-005 | — | Claude Coordenador |
| QA-004 | QA Agent | addons/arboria/*, project/scripts/* | concluído | GODOT-004 | — | Claude Coordenador |
| QA-005 | QA Agent | project/shaders/*, native/renderer/gpu/* | concluído | GPU-001 | — | Claude Coordenador |
| QA-006 | QA Agent | native/renderer/tests/* | concluído | Todas as alterações | — | Claude Coordenador |
| QA-007 | QA Agent | native/renderer/tests/* | concluído | CORE-007 | — | Claude Coordenador |
| QA-008 | QA Agent | native/renderer/* | concluído | Nenhuma | — | Claude Coordenador |
| QA-009 | QA Agent | docs/*, AGENT_TEST_EVIDENCE.md | concluído | Todas as tarefas | — | Claude Coordenador |
| QA-010 | QA Agent | native/renderer/tests/* | concluído | CORE-007 | — | Claude Coordenador |
| QA-011 | QA Agent | native/renderer/tests/* | concluído | CORE-007 | — | Claude Coordenador |
| QA-012 | QA Agent | native/renderer/tests/* | concluído | CORE-007 | — | Claude Coordenador |
| QA-013 | QA Agent | native/renderer/tests/* | concluído | CORE-007 | — | Claude Coordenador |
| QA-014 | QA Agent | addons/arboria/core/arboria_native_pipeline.gd, addons/arboria/core/arboria_mesh_loader.gd, project/scripts/arboria_native_pipeline.gd, project/scripts/arboria_massive_world_demo.gd | concluído | Nenhuma | 2026-11-02 | Claude Coordenador |
| QA-015 | QA Agent | native/renderer/tests/test_native_core.cpp, native/renderer/tests/test_arboria_advanced.cpp | concluído | QA-014 | 2026-11-02 | Claude Coordenador |

### Performance & Release Agent
| TASK_ID | AGENTE | ARQUIVOS | STATUS | DEPENDÊNCIAS | ÚLTIMA ALTERAÇÃO | REVISOR |
|---------|--------|----------|--------|--------------|------------------|---------|
| PERF-001 | Performance Agent | bench/*, validation/* | concluído | Nenhuma | — | Claude Coordenador |
| PERF-002 | Performance Agent | bench/*, validation/* | concluído | PERF-001 | — | QA Agent |
| PERF-003 | Performance Agent | native/renderer/*, bench/* | concluído | PERF-001 | — | QA Agent |
| PERF-004 | Performance Agent | native/renderer/* | concluído | PERF-003 | — | QA Agent |
| PERF-005 | Performance Agent | native/renderer/build_*/*, project/bin/* | concluído | CORE-007 | — | QA Agent |
| PERF-006 | Performance Agent | addons/arboria/plugin.cfg, docs/* | concluído | Nenhuma | — | QA Agent |
| PERF-007 | Performance Agent | project/bin/*, addons/arboria/bin/* | concluído | PERF-005 | — | QA Agent |
| PERF-008 | Performance Agent | docs/*, README* | concluído | Nenhuma | — | QA Agent |
| PERF-009 | Performance Agent | Todos os artefatos | concluído | Todas as tarefas | — | Claude Coordenador |

---

## Wave 2 — Integração (após Wave 1)

Geometry + Godot + Core: integrar compilador corrigido ao pipeline de produção  
Geometry + GPU: conectar refinamento e seleção LOD ao runtime gráfico  
GPU + Godot: validar renderização, profundidade, PBR e sombras  
Core + QA: executar testes de memória e concorrência  
Performance + QA: reconciliar benchmarks e verificar evidências  

---

## Wave 3–6 — Testes reais, correções, otimização, certificação

Conforme Seção 11 da Ordem Executiva.
