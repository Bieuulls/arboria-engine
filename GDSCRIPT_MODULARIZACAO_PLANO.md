# ARBORIA ENGINE — Plano de Modularização do GDScript

**Arquivo alvo:** `arboria_native_pipeline.gd` (2312 linhas, monolítico)  
**Cópias:** `addons/arboria/core/`, `project/addons/arboria/core/`, `project/scripts/`  
**Prioridade:** MÉDIA  
**Esforço estimado:** 1-2 semanas  
**Status:** Planejado (não iniciado)

---

## 1. Motivação

O arquivo `arboria_native_pipeline.gd` concentra toda a integração Godot↔C++ (RenderingDevice, GDExtension, culling, streaming, DAG, telemetria) em ~2300 linhas. Isso dificulta:

- Manutenção e revisão de código
- Testes isolados de subsistemas
- Onboarding de novos desenvolvedores
- Colaboração simultânea de múltiplos agentes/IA

---

## 2. Proposta de Divisão

| Novo arquivo | Responsabilidade | Linhas estimadas (do original) |
|--------------|------------------|--------------------------------|
| `arboria_native_pipeline.gd` | Orquestrador — inicialização, shutdown, chamada aos módulos, API pública | ~400 (fina) |
| `arboria_culling.gd` | Culling frustum, cone, Hi-Z, seleção LOD, DAG travessia | ~500 |
| `arboria_streaming.gd` | Gerenciamento de páginas VRAM, orçamento, eviction LRU, page fault | ~400 |
| `arboria_dag.gd` | Hierarquia DAG, grupos, cluster.group/refined, reconstrução incremental | ~300 |
| `arboria_stats.gd` | Telemetria, estatísticas de frame, contadores de visibilidade, benchmarks | ~300 |
| `arboria_render_pass.gd` | Dispatch compute, draw indirect, pipelines Vulkan, uniform sets | ~400 |

**Total:** ~2300 linhas redistribuídas em 6 arquivos focados.

---

## 3. Classes e Estruturas por Arquivo

### `arboria_native_pipeline.gd` (orquestrador)
- `class_name ArboriaNativePipeline` (mantido)
- `_shared_instance` singleton
- `MeshGPUResource` e `InstanceGPUData` (estruturas de dados compartilhadas)
- `rd: RenderingDevice`, `is_initialized`, `native_core`
- `default_*_tex`, `default_sampler`, `_texture_cache`, `_mesh_cache`
- Métodos públicos: `initialize()`, `shutdown()`, `register_mesh()`, `register_instance()`, `update_camera()`, `render_frame()`

### `arboria_culling.gd`
- `class ArboriaCulling` (extends RefCounted)
- Frustum plane extraction (6 planos)
- Frustum/cone/Hi-Z culling por cluster
- Seleção de LOD por erro de tela
- Travessia DAG top-down
- Métodos: `extract_frustum_planes()`, `test_frustum_sphere()`, `test_cone()`, `test_hiz()`, `cull_instance()`, `select_lod()`

### `arboria_streaming.gd`
- `class ArboriaStreaming` (extends RefCounted)
- Gerenciamento de páginas de geometria
- Orçamento VRAM, eviction LRU, page fault fallback
- Página raiz sempre residente
- Métodos: `register_page()`, `make_page_resident()`, `evict_lru()`, `update_streaming()`

### `arboria_dag.gd`
- `class ArboriaDAG` (extends RefCounted)
- Hierarquia DAG: grupo raiz, subdivisão recursiva
- `cluster.group`, `cluster.refined` vínculos
- Reconstrução incremental após modificação de geometria
- Métodos: `build_hierarchy()`, `traverse_top_down()`, `rebuild_incremental()`

### `arboria_stats.gd`
- `class ArboriaStats` (extends RefCounted)
- Contadores de culling, visibilidade, draw calls
- Frame p95, tempo de edição, DAG, upload
- Exportação para CSV/JSON
- Métodos: `record_frame()`, `get_report()`, `export_csv()`

### `arboria_render_pass.gd`
- `class ArboriaRenderPass` (extends RefCounted)
- Pipelines compute/raster Vulkan
- Uniform sets (camera, instance, culling)
- Draw indirect commands
- Hi-Z pyramid management
- Métodos: `dispatch_compute()`, `draw_indirect()`, `bind_pipelines()`

---

## 4. Estratégia de Implementação (Fases)

### Fase 1 — Extrair estruturas de dados (1-2 dias)
Mover `MeshGPUResource`, `InstanceGPUData` e constantes para um arquivo separado (`arboria_types.gd` ou manter no pipeline). Sem mudança de comportamento.

### Fase 2 — Extrair culling (3-4 dias)
Criar `arboria_culling.gd` com a lógica de frustum/cone/Hi-Z/LOD. O pipeline chama o módulo via instância.

### Fase 3 — Extrair streaming (2-3 dias)
Criar `arboria_streaming.gd` com gerenciamento de páginas VRAM.

### Fase 4 — Extrair DAG (2-3 dias)
Criar `arboria_dag.gd` com hierarquia e travessia.

### Fase 5 — Extrair stats e render pass (3-4 dias)
Criar `arboria_stats.gd` e `arboria_render_pass.gd`.

### Fase 6 — Refinar orquestrador (2-3 dias)
Reduzir `arboria_native_pipeline.gd` a um orquestrador fino que delega para os módulos.

### Fase 7 — Testes de regressão (2-3 dias)
Executar todos os testes GDScript existentes para garantir que nada quebrou.

---

## 5. Critérios de Aceitação

- [ ] `arboria_native_pipeline.gd` reduzido para < 600 linhas (orquestrador)
- [ ] Cada módulo tem responsabilidade única e clara
- [ ] Nenhuma funcionalidade perdida (todos os testes GDScript passam)
- [ ] Cópias sincronizadas em `addons/` e `project/addons/`
- [ ] Documentação atualizada com diagrama de dependências

---

## 6. Riscos

| Risco | Mitigação |
|-------|-----------|
| Quebra de referências entre módulos | Usar `preload` e instâncias explícitas; evitar acoplamento circular |
| Diferenças entre cópias addons/ e project/ | Aplicar mesma divisão em todas as 3 cópias |
| Regressão em testes existentes | Executar bateria completa após cada fase |
| Perda de performance por chamada cruzada | Manter caminhos críticos (culling, render) em classes leves |
