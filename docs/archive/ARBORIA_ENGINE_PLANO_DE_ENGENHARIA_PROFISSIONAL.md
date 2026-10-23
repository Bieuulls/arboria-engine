# ARBORIA ENGINE — PLANO DE ENGENHARIA E EXECUÇÃO

**Referência técnica:** pacote `ARBORIA_ENGINE_OFFICIAL(20261022-184935).rar` examinado em 22/10/2026.  
**Escopo:** renderizador de geometria virtualizada com Godot 4.7.2 Forward+ / Vulkan, RTX 3050 6 GB como alvo de desenvolvimento.  
**Classificação atual:** protótipo funcional, integração incompleta. Nenhuma métrica de desempenho sustentado foi comprovada no hardware-alvo nesta análise.

## 0. Decisão arquitetural obrigatória

Não reconstruir Baker, `.vgmesh`, DAG nem o culling já implementado. NÃO confundir C++ com integração ao renderizador: o RenderingDevice é a abstração gráfica legítima do Godot; o que precisa mudar é a propriedade e o ciclo de vida dos recursos, a integração aos passes e a submissão segura do trabalho gráfico.

**Arquitetura-alvo:** `Editor e cenas Godot → VirtualMeshInstance3D/Resource → ArboriaRenderWorld (C++) → GPUResourceManager → GPUCulling/DAG → IndirectRenderer → integração render passes Godot Forward+ → RenderingDevice/Vulkan`.

Criar uma **cópia/branch isolada do Godot 4.7.2** para os pontos que não podem ser implementados corretamente pelo CompositorEffect/GDExtension. A integração à shadow pass e ao depth prepass exige prova real; `POST_OPAQUE` não substitui essas etapas. Preservar a variante experimental como fallback. Não editar o motor instalado nem sobrescrever a árvore usada por outro agente.

## 1. G0 — Base reprodutível e critérios objetivos (bloqueante)

Entregar repositório Git com commit-base congelado, documentação do compilador/SCons/CMake/Godot, scripts de build de um comando, conjunto mínimo de ativos e cenas; preservar a captura atual para comparação. Separar `engine-fork`, `runtime`, `baker` e `tests` em pastas/branches controladas. Registrar inventário de recursos/ownership. 

**Passa quando:** build reproduzível de 0, teste do `.vgmesh` real obrigatório (sem fallback sintético silencioso), logs de build, renderer identificado e uma cena que falha se não renderizar.

## 2. G1 — ABI e runtime nativo seguro (bloqueante)

Arquivos de origem: `native/renderer/integration/vg_gdextension.cpp`, `gpu/vg_gpu_driver.h`, `gpu/vg_compute_dispatch.cpp`, `gpu/vg_indirect_renderer.cpp`, `core/vg_runtime.*`, `project/scripts/arboria_native_pipeline.gd`.

- Eliminar ponte ad hoc de `Variant` baseada em arrays de 32 bytes, ou encapsulá-la com tipos e ciclo de vida corretos da API. Preferir bindings oficiais de `godot-cpp` ou módulo nativo.
- Garantir tipos de argumentos e retornos, validação de tamanho de arrays, RIDs, thread de renderização e tratamento de erros. Nunca ignorar retorno de `render_scene_batch`.
- Distinguir sucesso de chamada de API de sucesso visual/renderização GPU; instalar labels de depuração e teste que comprove execução do pass.
- Transferir propriedade de buffers, pipelines e uniform sets para RAII/C++; GDScript pode comunicar câmera, transforms e propriedades; não criar ou liberar recursos gráficos em runtime.
- Definir contratos `initialize`, `register_mesh`, `register_instance`, `update_instance`, `render_frame`, `release_instance`, `unload_mesh`, `shutdown` com resultados explícitos e geração de IDs contra handles obsoletos.

**Passa quando:** pipeline principal chama C++, com resources criados e destruídos no backend, sem chamadas `compute_list_dispatch`, `draw_list_draw_indirect`, `storage_buffer_create`, `render_pipeline_create` ou `free_rid` para o ARBORIA dentro do GDScript. Nenhum sucesso é declarado caso uma etapa falhe. Testes de carga/descarrega repetidos sem vazamentos.

## 3. G2 — Integração real com Forward+ (bloqueante)

Escolher e implementar, quando exigido, um módulo/patch na cópia do Godot 4.7.2 com pontos de integração no renderer. Não chamar um `CompositorEffect POST_OPAQUE` de integração opaca completa.

- Incorporar geometria ao passe de profundidade e renderização opaca adequado, com reverse-Z, frustum/clipping e estados corretos.
- Incorporar a shadow maps de luz direcional inicialmente; depois SpotLight3D/OmniLight3D, de acordo com o suporte da API. Implementar receber/projetar sombras, não apenas marcar `cast_shadows=true`.
- Participação consistente no modelo de materiais e iluminação, incluindo mapa de normais, tangentes, UV, alpha-test quando suportado; separar suporte PBR parcial de integração nativa.
- Tratar resize de viewport, alterações de resolução, MSAA, múltiplas câmeras, estado invisível, device loss quando recuperável.

**Passa quando:** cenas de geometria mista com profundidade nos dois sentidos, uma rocha projetando sombra sobre MeshInstance3D e recebendo sombra de MeshInstance3D, resultados estáveis durante movimentação de câmera, sem texturas sobrepostas que simulem passes.

## 4. G3 — GPU-driven global e instancing escalável (bloqueante)

Criar `RenderWorld`, `GPUScene`, buffers de instâncias e tabela de materiais; upload de malha 1 vez por recurso, índices de instâncias com transform/LOD/material e ciclo de vida claro. Consolidar envio por batches de material/pipeline; minimizar dispatch e draw por instância, medindo antes/depois. Preserve compactação indireta e DAG.

- Frustum/cone culling por instância e cluster no espaço correto.
- Seleção LOD por erro projetado usando FOV real da câmera, viewport e métricas robustas; estabilidade temporal e crack-free.
- Comandos GPU indirect sem leitura CPU para escolher clusters.
- Sincronização correta entre uploads, Compute, indirect e render passes, respeitando threading e barreiras do RenderingDevice.

**Passa quando:** 1, 80, 500 e 1000 instâncias funcionam nas cenas de teste sem crescimento desnecessário de recursos por instância; desativar o culling altera de modo consistente a carga geométrica; GPU trace confirma o caminho indirect e a contagem de dispatches/draws cresce por lotes, não necessariamente 1:1 com cada objeto.

## 5. G4 — Memória GPU e telemetria (bloqueante)

- Substituir estimador `VGBufferManager` por gerenciador efetivo de buffers com ownership, reutilização, compartilhamento de mesh, realocação, budget/VRAM, descarte seguro após uso pela GPU e estatísticas de memória medida.
- Eliminar `buffer_get_data()` no loop, inclusive na periodicidade de 15 frames. Usar `buffer_get_data_async()` quando suportado, ou staging readback com fence e latência documentada. Não denominar async uma leitura síncrona periódica.
- Adicionar timestamps de GPU e tracing separados: upload, cull, compact, indirect, shadow, opaque. Monitorar CPU main/render thread, VRAM, p50/p95/p99 frame time e número de submissions.

**Passa quando:** nenhuma espera CPU↔GPU periódica no caminho normal; telemetria não bloqueante; 20 minutos de carga/descarga e resize sem crescimento acumulado de VRAM; métricas reais com método de coleta documentado.

## 6. G5 — Correção geométrica, materiais e importação

- Baker: conservar o que já passa, adicionar testes de equivalência geométrica e material em malhas reais de tamanhos e topologias variadas.
- Manter consistência de bordas nos LODs, preservar UV/tangent/normal, tratar materiais por submesh, winding/backface, mirrored transform/scale, limites de buffers, geometria degenerada, negative scales e zero triangles.
- GLB/glTF e OBJ: importar de forma reproduzível para `.vgmesh` com identificação de materiais e logs dos recursos não suportados; evitar converter silenciosamente conteúdos animados/skinned se pipeline não suportar.

**Passa quando:** imagens de referência com paridade perceptual fundamentada em testes numéricos, zero rachaduras visíveis nas cenas de transição especificadas, importação determinística por seed/opções, arquivos inválidos rejeitados sem crash.

## 7. G6 — Hi-Z / occlusion culling (somente após G1–G5)

Construir mip chain real da pirâmide de profundidade; selecionar redução coerente com reverse-Z; usar profundidade da cena/prepass correto, com heurísticas conservadoras e hysteresis temporal; invalidar/reinicializar histórico em teleport/resize/cortes de câmera. Testar objetos que emergem por trás de oclusores e objetos finos.

**Passa quando:** sem objetos falsamente desaparecendo; número de clusters visíveis reduz onde há oclusão comprovada e há ganho de GPU time medido. O shader isolado de redução não configura funcionalidade concluída.

## 8. G7 — Streaming virtual de geometria (após G6)

Formato `.vgmesh` versionado com páginas e dependências, páginas raiz resident, cache GPU com budget, loading assíncrono, IO/decompressão, LRU/prioridade, paginação e fallback de LOD quando dados ainda não residem. Precisa evitar stalls, popping e out-of-memory. Testes com câmera percorrendo mundo maior que VRAM.

**Passa quando:** cena com dataset > VRAM em armazenamento funciona dentro de budget, com frames e contadores de page faults medidos; nenhuma referência inválida após eviction.

## 9. G8 — Ferramentas de editor, validação e lançamento

Editor: importação GLB→.vgmesh, `VirtualMeshInstance3D` com propriedades de LOD/material/bounds/visibilidade, debug de clusters e VRAM, modo Godot convencional como fallback, erros explícitos, documentação de compatibilidade. Estabelecer CI C++, shader compilation, cenas de referência, GitHub Issues e contribuição externa.

**Critério de release alfa:** todos G0–G5 aprovados no alvo; G6/G7 podem estar declarados experimentais ou indisponíveis, mas jamais anunciados como completos. Reprodutibilidade independente, crash-free em stress, performance comparada com mesh padrão em condições equivalentes.

## 10. Métricas reais — contrato

- Cenários fixos: 1 malha isolada, 80 instâncias, 500 instâncias, 1.000 instâncias e grandes geometrias distintas.
- Mesma câmera, resolução 1920×1080, efeitos, viewport, assets e modo VSync para comparações.
- Separar warm-up de medição, coletar pelo menos 1.000 frames por cena, registrar CPU/GPU frame time p50/p95/p99, VRAM, draw calls/dispatches e stutters.
- Meta operacional proposta para uma cena de referência na RTX 3050: 60 FPS (16,67 ms/frame); é meta a validar e ajustar conforme complexidade, não resultado já alcançado nem promessa universal.
- Rejeitar benchmark sintético, `FPS=1` em screenshot como evidência suficiente, contadores escritos como constantes e testes que passam sem geometria na tela.

## 11. Organização de engenharia multiagente

- **Lead/Integrador:** dono do contrato do backend e merge; apenas ele integra branches na main.
- **Agente Runtime C++:** G1, ownership e API; não edita render passes do fork.
- **Agente Renderer Godot:** G2, depth, opaque, shadow no fork isolado; não edita Baker.
- **Agente GPU Geometry:** G3, LOD/culling/draw; branch isolada.
- **Agente QA/Performance:** G0/G4 e testes contínuos; corrige issues em branch própria.
- **Agente Assets/Import:** G5, depois de API de dados congelada.

Cada PR exige patch, comandos de build, testes que falhavam antes e passam depois, captura real se gráfico, limites conhecidos. Proibida edição simultânea do mesmo arquivo na mesma pasta; apenas merges revisados. Fluxo de desenvolvimento: issue → branch/worktree → implementação → teste → revisão → merge. Não solicitar nova auditoria geral em cada entrega.

## 12. ORDEM IMEDIATA AO CODEX/ANTIGRAVITY

**Fazer somente G0, G1 e a prova mínima de G2 na próxima entrega.** Não iniciar Hi-Z, streaming, botânica, IA nem novos efeitos. Primeira entrega deve conter:

1. Um único contrato de acesso GPU C++ com ownership real e tratamento de todos os erros.
2. API GDExtension limpa, sem ponte de Variants crus manualmente empacotados, ou módulo nativo corretamente tipado.
3. GDScript reduzido a cena/propriedades, sem cria/destrói GPU e sem Compute/Draw.
4. Vertical slice com uma malha ARBORIA no verdadeiro caminho nativo definido e prova de depth + uma shadow map. Caso o compositor não suporte, implementar a alteração no fork de Godot; sem afirmar integração Forward+ completa enquanto shadow não participar.
5. Compilação reproduzível e teste de renderização real mostrando a malha, visualização GPU trace e erros 0.

**Aprovação somente com execução e provas, não com mensagens 'OK' ou apenas classes compiladas.**
