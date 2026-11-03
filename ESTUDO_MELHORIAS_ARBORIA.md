# ARBORIA ENGINE — Estudo Completo de Melhoria e Refinamento

**Versão analisada:** OFICIAL_FINAL_CLEAR(1)
**Data:** 2026-11-01
**Escopo:** Código nativo C++ (GDExtension), shader de culling GPU, integração Godot/GDScript

---

## 1. RESUMO EXECUTIVO

O ARBORIA ENGINE possui uma arquitetura sólida de geometria virtualizada tipo Nanite com DAG, culling hierárquico, submissão global única de compute + indirect draw, e geometria mutável (COW). Todos os 28 testes nativos passam, a compilação é limpa (64/64 etapas, zero erros) e as DLLs estão atualizadas nos locais canônicos.

No entanto, para elevar o código a nível de produção comercial, existem oportunidades concretas de melhoria divididas em quatro níveis de prioridade:

| Prioridade | Área | Impacto | Esforço |
|------------|------|---------|---------|
| CRÍTICO | Segurança de threads / data races | Alta estabilidade | Médio |
| CRÍTICO | Sincronização Vulkan entre passes | Correção de renderização | Médio |
| ALTO | Performance do GPU Scene (build_gpu_instance_buffer por frame) | Alta escalabilidade | Médio |
| ALTO | Tratamento de erros e logging | Debugabilidade | Baixo |
| MÉDIO | Modularização do GDScript (~2300 linhas) | Manutenibilidade | Alto |
| MÉDIO | Parâmetros hardcoded no shader | Flexibilidade/Tuning | Baixo |
| BAIXO | Sanitizers (ASan/TSan) no build | Qualidade de código | Baixo |
| BAIXO | Smart pointers (unique_ptr vs shared_ptr) | Memória/performance | Médio |

---

## 2. ANÁLISE POR COMPONENTE

### 2.1 Mesh Registry (`arboria_mesh_registry.cpp/.h`)

**Pontos fortes:**
- Pool geracional (`GenerationalPool`) com rejeição automática de handles obsoletos
- Deduplicação por caminho de arquivo (`m_path_to_handle`)
- Offsets globais acumulados para clusters/vertices/triângulos
- Mutex protegendo todas as operações de leitura e escrita

**Pontos fracos:**
- `register_mesh()` segura `m_mutex` e chama `register_mesh_resource()` que modifica estado compartilhado SEM re-adquirir o mutex. Quando chamado de caminhos externos (ex.: `VGRuntime::register_mesh_from_memory`), há risco de data race.
- `get_mesh_info_by_index()` retorna ponteiro bruto sem indicar se o handle ainda é válido (geraçao pode ter mudado).
- Nenhuma proteção contra registro concorrente de múltiplas threads para o mesmo caminho.

### 2.2 Instance Registry (`arboria_instance_registry.cpp/.h`)

**Pontos fortes:**
- Pool geracional para instâncias com rejeição de handles stale
- `build_gpu_instance_buffer()` computa bounds, matriz normal, flags de visibilidade espelhada
- Integração com MutableGeometryOverlay para geometria mutável por instância
- Cálculo correto de AABB no mundo (método de Jim Arvo)

**Pontos fracos:**
- `build_gpu_instance_buffer()` itera TODOS os slots (incluindo inativos) e chama `ArboriaMeshRegistry::instance().get_mesh_info()` dentro do loop — potencial lock contention e custo O(N) desnecessário.
- Nenhum cache de buffers GPU; reconstrução completa a cada frame.
- `InstanceRecord` armazena `mutable_overlay` como `shared_ptr` — risco de retenção de memória se overlay não for liberado corretamente.

### 2.3 Scene Bridge (`arboria_scene_bridge.cpp/.h`)

**Pontos fortes:**
- Delegação correta ao `ArboriaInstanceRegistry` como fonte única de verdade
- Resolução de Handle da malha com geração correta via `get_mesh_info_by_index()`
- `unregister_instance_handle()` limpa registro global e local

**Pontos fracos:**
- Duplicidade de estado: mapas locais `m_instances` + `m_id_to_handle` paralelizam o registry global.
- `get_instance_by_handle()` faz busca linear O(N) através de `m_id_to_handle`.
- `clear()` não reseta `m_next_instance_id` de forma atômica com os registros (possível race em shutdown concorrente).

### 2.4 GPU Scene (`arboria_gpu_scene.cpp/.h`)

**Pontos fortes:**
- Culling em nível de instância (frustum) antes de iterar clusters — descarte antecipado eficiente.
- Suporte a LOD forçado e Auto DAG com seleção hierárquica.
- Integração com MutableGeometryOverlay para substituição de clusters.
- `dispatch_global_cull()` e `draw_global_indirect()` implementam 1 dispatch + 1 draw para toda a cena.

**Pontos fracos:**
- `simulate_cull_scene()` chama `build_gpu_instance_buffer()` a cada chamada — custo O(N) de CPU por frame mesmo sem mudanças.
- `build_scene_uniforms()` também chama `build_gpu_instance_buffer()` — chamada duplicada.
- Sem barreira de memória Vulkan entre o compute de culling e o draw indirect — risco de ler dados parcialmente escritos na GPU.
- `inst_handle` reconstruído com `(inst.instance_id, inst.resource_generation)` — correto, mas depende que `resource_generation` esteja sincronizado com o pool geracional.

### 2.5 Streaming Manager (`arboria_streaming_manager.cpp/.h`)

**Pontos fortes:**
- Chave `m_profiles` por `mesh_handle.index` (uint32_t) — correto após a correção.
- Página raíz sempre residente; páginas de detalhe evicted por LRU sob pressão.
- Fallback seguro para cluster da página raíz durante page faults.

**Pontos fracos:**
- `update()` chama `build_gpu_instance_buffer()` a cada frame para calcular proximidade da câmera — custo CPU elevado em cenas com muitas instâncias.
- Sem throttling de atualização (rodar a cada N frames seria suficiente para streaming).
- Orçamento de VRAM fixo; sem ajuste dinâmico baseado em uso real.

### 2.6 Compute Dispatch (`arboria_compute_dispatch.cpp`)

**Pontos fortes:**
- Verificação de retorno em todas as chamadas `compute_list_*`.
- `extract_frustum_planes()` com normalização e fallback para plano inválido.
- `simulate_cull_offline()` para validação offline do culling.

**Pontos fracos:**
- Nenhum log de erro quando chamadas Vulkan falham — apenas retorna `false`.
- `dispatch_cull_clusters_batch()` ignora `valid`/`oob` de `get_indexed` para `compute_sets_array` (usa apenas `gx`).

### 2.7 Indirect Renderer (`arboria_indirect_renderer.cpp`)

**Pontos fortes:**
- `validate_draw_command()` com validação de `vertex_count`, `instance_count`, `first_vertex`, `first_instance`.
- `build_initial_draw_command()` com `vertex_count = 384` (128 triângulos × 3 vértices).
- `draw_indirect_batch()` com loop sobre arrays de sets e buffers.

**Pontos fracos:**
- `draw_indirect_native()` não verifica retorno de `draw_list_bind_uniform_set` de forma consistente (usa `if (ok) ok = ...`).
- Nenhum estado de pipeline cacheado entre frames.

### 2.8 Shader de Culling (`cull_clusters_global.glsl`)

**Pontos fortes:**
- `atomicAdd(total_clusters_evaluated, 1u)` dentro de `if (visible)` — conta apenas clusters aprovados.
- DAG hierárquico top-down com early-out.
- Suporte a LOD forçado e automático.
- Hi-Z oclusão e cone culling.

**Pontos fracos:**
- `local_size_x = 1, local_size_y = 64` hardcoded — não se adapta a diferentes GPUs.
- Mágicos: `radius * 2.5`, `radius * 2.0`, `mip` limitado a 11 níveis.
- Sem push constants para parâmetros de culling (frustum, cone, Hi-Z enable/disable).
- `total_clusters_evaluated` nome enganoso se conta apenas visíveis (deveria ser `total_clusters_visible`).

### 2.9 GDScript Pipeline (`arboria_native_pipeline.gd`)

**Pontos fortes:**
- ~2300 linhas de integração com RenderingDevice API.
- Duplo caminho de renderização (per-instance vs global single dispatch).
- Estatísticas e telemetria.

**Pontos fracos:**
- Arquivo monolítico de ~2300 linhas — difícil de manter e revisar.
- Não foi possível revisar integralmente neste estudo (arquivo muito grande).

---

## 3. RECOMENDAÇÕES DETALHADAS

### PRIORIDADE CRÍTICA — Estabilidade e Correção

#### 3.1. Corrigir data race no Mesh Registry
**Problema:** `register_mesh_resource()` modifica `m_mesh_pool`, `m_path_to_handle`, `m_total_clusters` etc. sem segurar o mutex quando chamado de fora de `register_mesh()`.

**Solução:**
```cpp
// Método privado chamado SOB lock
Handle register_mesh_resource_locked(const std::string& path, std::shared_ptr<VGMeshResource> resource);

// Método público que adquire o lock
Handle register_mesh_resource(const std::string& path, std::shared_ptr<VGMeshResource> resource) {
    std::lock_guard<std::mutex> lock(m_mutex);
    return register_mesh_resource_locked(path, resource);
}
```

**Impacto:** Elimina risco de corrupção de pool em acesso concorrente.
**Esforço:** Médio (1-2 dias)

#### 3.2. Adicionar barreiras de memória Vulkan entre compute e draw indirect
**Problema:** `dispatch_global_cull()` escreve contadores e buffer de itens visíveis via compute; `draw_global_indirect()` lê esses dados via indirect draw. Sem barreira, a GPU pode executar o draw antes que o compute termine.

**Solução:** Adicionar `vkCmdPipelineBarrier` (ou equivalente via RenderingDevice) entre os dois passes, com:
- `srcStageMask = VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT`
- `dstStageMask = VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT`
- `srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT`
- `dstAccessMask = VK_ACCESS_INDIRECT_COMMAND_READ_BIT | VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT`

**Impacto:** Garante correção de renderização em GPUs modernas com execução fora de ordem.
**Esforço:** Médio (2-3 dias)

---

### PRIORIDADE ALTA — Performance e Escalabilidade

#### 3.3. Cache incremental do GPU Instance Buffer
**Problema:** `build_gpu_instance_buffer()` reconstrói todo o buffer a cada frame, mesmo quando poucas instâncias mudaram. Com 2.000 instâncias, isso é O(N) desnecessário por frame.

**Solução:** Implementar sistema de dirty flags por instância:
- `InstanceRecord` ganha `bool dirty = false`.
- `set_transform()`, `set_visibility()`, `set_lod_parameters()` marcam `dirty = true`.
- `build_gpu_instance_buffer()` aceita parâmetro `bool full_rebuild = false`; se falso, processa apenas instâncias sujas e as marca limpas.
- Manter `std::vector<GPUInstanceData>` persistente entre frames.

**Impacto:** Reduz CPU por frame de O(N) para O(M) onde M = instâncias modificadas.
**Esforço:** Alto (3-5 dias)

#### 3.4. Otimizar `build_scene_uniforms()` e `simulate_cull_scene()`
**Problema:** Ambas chamam `build_gpu_instance_buffer()` — trabalho duplicado por frame.

**Solução:** Compartilhar o resultado do buffer entre as duas chamadas, ou calcular `total_work_items` a partir do cache incremental (soma de `cluster_count` apenas de instâncias ativas).

**Impacto:** Redução de ~50% no CPU gasto na construção de uniforms e culling simulado.
**Esforço:** Médio (1-2 dias)

#### 3.5. Throttling do Streaming Manager
**Problema:** `streaming_update()` roda a cada frame e reconstrói o buffer de instâncias para calcular proximidade da câmera.

**Solução:** Executar streaming a cada N frames (ex.: 4 ou 8) ou apenas quando a câmera se moveu mais que um limite. Manter páginas raízes residentes sempre.

**Impacto:** Redução de CPU em cenas com streaming ativo.
**Esforço:** Baixo (1 dia)

---

### PRIORIDADE MÉDIA — Manutenibilidade e Qualidade

#### 3.6. Tratamento de erros estruturado
**Problema:** Muitas funções retornam `bool` genérico sem contexto de erro. Chamadores nem sempre verificam.

**Solução:** Introduzir `enum class ArboriaError` + struct `Result<T>` (ou `std::expected` se C++23 estiver disponível). Exemplos:
```cpp
enum class ArboriaError {
    OK,
    InvalidHandle,
    MeshNotFound,
    RegistryFull,
    VulkanCallFailed,
    OutOfMemory
};
```

**Impacto:** Debuggação muito mais rápida; falhas não são silenciosas.
**Esforço:** Alto (refatoração ampla, 5-7 dias)

#### 3.7. Modularizar GDScript (~2300 linhas)
**Problema:** `arboria_native_pipeline.gd` é um arquivo monolítico.

**Solução:** Dividir em classes/arquivos por responsabilidade:
- `arboria_culling.gd` — lógica de culling frustum/Hi-Z
- `arboria_streaming.gd` — gerenciamento de páginas VRAM
- `arboria_dag.gd` — travessia DAG e seleção LOD
- `arboria_stats.gd` — telemetria e estatísticas
- Manter `arboria_native_pipeline.gd` como orquestrador

**Impacto:** Código mais fácil de manter, revisar e testar isoladamente.
**Esforço:** Alto (1-2 semanas)

#### 3.8. Parâmetros configuráveis no shader
**Problema:** Valores hardcoded no GLSL (workgroup size, raios de proximidade, níveis de mip).

**Solução:** Mover para `GlobalSceneUniforms` ou push constants:
- `vec4 culling_params` (x = frustum_enable, y = cone_enable, z = hiz_enable, w = pad)
- `float proximity_guard_radius`
- `uint max_hiz_mip_level`

**Impacto:** Tuning por cena/platforma sem recompilar shader.
**Esforço:** Baixo (1-2 dias)

#### 3.9. Sanitizers (ASan/TSan/UBSan) no build
**Problema:** Nenhuma detecção automática de vazamentos, data races ou comportamento indefinido.

**Solução:** Adicionar alvos CMake:
- `arboria_native_asan` com `-fsanitize=address,undefined`
- `arboria_native_tsan` com `-fsanitize=thread`
- Rodar nos testes de regressão em CI

**Impacto:** Detecção precoce de bugs de memória e concorrência.
**Esforço:** Baixo (1-2 dias)

#### 3.10. Substituir `shared_ptr` por `unique_ptr` onde apropriado
**Problema:** `VGMeshResource` e `MutableGeometryOverlay` usam `shared_ptr` amplamente, com overhead de contagem atômica e risco de referências circulares.

**Solução:** Avaliar propriedade única (`unique_ptr`) para recursos de malha no `GenerationalPool`, com `shared_ptr` apenas quando múltiplos owners são realmente necessários (overlays compartilhados).

**Impacto:** Redução de overhead atômico e melhor previsibilidade de memória.
**Esforço:** Médio (3-5 dias)

---

### PRIORIDADE BAIXA — Polimento e Observabilidade

#### 3.11. Sistema de logging com níveis
**Problema:** Uso direto de `std::cout`/`std::cerr` sem níveis, rotação ou destino configurável.

**Solução:** Logger simples com níveis (DEBUG/INFO/WARN/ERROR), saída para arquivo opcional, e macros que podem ser desabilitadas em release.

**Impacto:** Melhor observabilidade em produção no Godot.
**Esforço:** Baixo (1-2 dias)

#### 3.12. Renomear contador telemetria
**Problema:** `total_clusters_evaluated` conta apenas clusters visíveis (dentro de `if (visible)`), mas o nome sugere "avaliados".

**Solução:** Separar contadores:
- `total_clusters_evaluated` — todos os clusters considerados
- `total_clusters_visible` — aprovados pelo culling
- `total_clusters_submitted` — efetivamente gravados no buffer de saída

**Impacto:** Telemetria precisa para debugging e otimização.
**Esforço:** Baixo (1 dia)

---

## 4. ROADMAP DE IMPLEMENTAÇÃO

### Fase 1 — Estabilidade (Semanas 1-2)
1. Corrigir data race no Mesh Registry (mutex em `register_mesh_resource`)
2. Adicionar barreiras de memória Vulkan entre compute e indirect draw
3. Adicionar sanitizers (ASan/TSan) ao build e rodar testes

### Fase 2 — Performance (Semanas 3-5)
4. Cache incremental do GPU Instance Buffer (dirty flags)
5. Otimizar `build_scene_uniforms()` / `simulate_cull_scene()` (compartilhar buffer)
6. Throttling do Streaming Manager

### Fase 3 — Qualidade e Manutenibilidade (Semanas 6-8)
7. Tratamento de erros estruturado (`Result<T>` / `ArboriaError`)
8. Modularizar GDScript em múltiplos arquivos
9. Parâmetros configuráveis no shader (push constants/uniforms)

### Fase 4 — Polimento (Semanas 9-10)
10. Sistema de logging com níveis
11. Renomear contadores de telemetria
12. Avaliar `unique_ptr` para recursos de malha

---

## 5. IMPACTO ESPERADO

| Métrica | Antes | Depois (estimado) |
|---------|-------|-------------------|
| CPU por frame (2.000 instâncias) | ~37ms (edição) + ~24ms (DAG) | Redução de 30-50% com cache incremental |
| Data races | Potencial (Mesh Registry) | Eliminado |
| Correção de renderização | Risco sem barreira Vulkan | Garantido com barreira |
| Debuggabilidade | Logs básicos `cout` | Logs com níveis + sanitizers |
| Manutenibilidade (GDScript) | 1 arquivo de 2300 linhas | Módulos por responsabilidade |

---

## 6. CONCLUSÃO

O ARBORIA ENGINE está funcionalmente correto e estável (28/28 testes passam). As melhorias mais críticas são **segurança de threads no Mesh Registry** e **barreiras de memória Vulkan entre compute e draw indirect** — ambas afetam estabilidade e correção em produção. As melhorias de performance (cache incremental, throttling de streaming) trazem o maior ganho de escalabilidade para cenas grandes.

Recomendo iniciar pela Fase 1 (estabilidade) antes de qualquer otimização de performance, pois correções de performance sobre código com data races podem mascarar ou introduzir novos bugs difíceis de reproduzir.