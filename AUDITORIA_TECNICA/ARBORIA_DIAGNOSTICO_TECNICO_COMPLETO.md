# ARBORIA — diagnóstico técnico (21/10/2026)

## Resumo executivo
O Baker C++ e a validação estrutural ARBORIA2 v2 têm evidência automatizada positiva (17/17 testes). O pipeline RenderingDevice, GPU culling, indirect draw e a integração visual nativa ainda carecem de comprovação end-to-end reproduzível. A existência de chamadas de API não demonstra sua execução correta no hardware. Não existe medição independente de FPS, VRAM ou comparação A/B/C/D nesta auditoria.

## Inventário e conexões
- `tools/baker/src/vg_baker_main.cpp` e `tools/baker/CMakeLists.txt`: importação OBJ, meshoptimizer, simplificação, clusters, DAG e gravação binária.
- `tests/test_suite.py`, `tests/*.vgmesh`: testes de integridade, corrupção e geometria.
- `project/scripts/vgmesh_loader.gd`: leitura no projeto Godot.
- `project/scripts/vg_gpu_pipeline.gd`: RenderingDevice, compute, buffers, despacho e desenho indireto; fallback MultiMesh.
- `project/shaders/cull_clusters.glsl`: seleção/culling e contador atômico de instâncias visíveis.
- `project/shaders/vg_cluster_render.gdshader`: shader de geometria.
- `project/scripts/main_viewer.gd`, `project/scenes/main_viewer.tscn`, `project/project.godot`: apresentação e integração de cena Forward+.
- `project/scripts/benchmark_fase3.gd` e scripts `test_*.gd`: instrumentação e cenários de validação.
- `D:/ARBORIA_ENGINE/ARBORIA_MANAGER/03_GODOT_CORE_MODULE`: `register_types.cpp/.h`, `virtual_mesh_instance_3d.h`, `config.py`; presença de código não prova compilação ou carregamento no Godot oficial.
- `AUDITORIA_FASE3_FINAL`: relatórios, capturas e CSV históricos; são evidências anteriores, sem revalidação gráfica nesta execução.
- `tools/baker/thirdparty/meshoptimizer`: dependência externa vendorizada; excluída do pacote para reduzir volume.
- Diretórios paralelos na raiz `D:/ARBORIA_ENGINE`: `05_PROJECT_GODOT`, `04_ASSETS_PBR`, `bin`, `_ARQUIVO_MORTO`; não há evidência suficiente para classificar duplicações como descartáveis.

## Estado dos componentes — classificação baseada em evidência
| Recurso | Classificação | Evidência / ressalva |
|---|---|---|
| Importação OBJ, meshlets, simplificação, serialização ARBORIA2 v2, DAG estrutural e LOD0 | FUNCIONAL E TESTADA nos cenários da suíte | `tests/test_suite.py`, `testes_log.txt`; não prova escalabilidade universal |
| Erro projetado e seleção hierárquica contínua | PARCIALMENTE IMPLEMENTADA | Baker/DAG e compute existem; transições visuais e crack-free não verificadas |
| GPU frustum/normal cone culling | IMPLEMENTADA, MAS NÃO VALIDADA | `cull_clusters.glsl`, despacho em `vg_gpu_pipeline.gd` |
| GPU-driven rendering e indirect drawing | IMPLEMENTADA, MAS NÃO VALIDADA | `draw_list_draw_indirect` em `vg_gpu_pipeline.gd`; falta captura GPU conclusiva |
| Instâncias e fallback MultiMesh | PARCIALMENTE IMPLEMENTADA | `vg_gpu_pipeline.gd`; custo de instâncias descartadas não medido |
| Vertex pulling, formatos, barreiras, vida útil de recursos | IMPLEMENTADA, MAS NÃO VALIDADA | shaders/pipeline; requer instrumentação gráfica |
| Hi-Z e oclusão, streaming de páginas, residência e cache VRAM | NÃO IMPLEMENTADA ou não localizada de forma demonstrável | sem teste ou subsistema verificável nesta inspeção |
| Visibility Buffer, Material Resolve, rasterização híbrida compute | NÃO IMPLEMENTADA ou não demonstrada | sem evidência operacional |
| Forward+ PBR, sombras, iluminação dinâmica e módulo nativo compilado | IMPLEMENTADA, MAS NÃO VALIDADA / integração incompleta | projeto Forward+ e código de módulo; sem teste nativo conclusivo |
| Escalabilidade entre GPUs | NÃO VALIDADA | nenhuma matriz de dispositivos medida |

## GPU — respostas às questões obrigatórias
1. Compute: há chamada de despacho em `vg_gpu_pipeline.gd:609-616`, mas execução efetiva na GPU não foi observada nesta sessão.
2. Culling influencia draw: o shader incrementa `instance_count` (`cull_clusters.glsl:134`) e há desenho indireto; dependência end-to-end ainda não validada.
3. Clusters descartados: custo residual de instâncias/vertex work não medido.
4. Leitura GPU→CPU: leitura assíncrona aparece em `vg_gpu_pipeline.gd:652`; ausência de bloqueios por frame não foi comprovada.
5. Argumentos indiretos: chamadas `draw_list_draw_indirect` em `vg_gpu_pipeline.gd:921,984`; consumo correto não confirmado por captura.
6. Buffers/samplers: compatibilidade não validada em GPU.
7. Vertex pulling: fidelidade visual de posição/índice/normal/UV pendente.
8. Barreiras compute→draw: correção e visibilidade de memória pendentes de inspeção/captura Vulkan.
9. Recursos: não há teste prolongado de vazamentos ou acessos inválidos.
10. Fallback: `vg_gpu_pipeline.gd:365,431` utiliza MultiMesh; critérios de comutação precisam ser exercitados em modo gráfico.

## Erros confirmados e limites
- Execução `godot --headless --path project --quit` com comando `godot` simples: falhou porque não estava no PATH (erro de ambiente, não defeito do motor).
- Com executável absoluto Godot 4.7.2, headless terminou com exit 0 mas registrou `ERRO CRITICO: RenderingDevice Vulkan indisponivel!` em `project/scripts/vg_gpu_pipeline.gd:75` (chamado por `main_viewer.gd:58`). Isso comprova apenas indisponibilidade no teste headless; não determina funcionamento em janela com Vulkan.
- Defeito de desenho, sincronização ou PBR: NÃO comprovado; classificar como risco técnico a testar.

## Benchmarks
Há APIs de timestamps GPU (`vg_gpu_pipeline.gd:636-643`) e scripts/CSV históricos. Não foi medida nesta execução a origem do valor antigo de ~3,6 ms. Não foram obtidos FPS, VRAM, draw calls, triângulos efetivos nem resultados controlados A/B/C/D. Valores de testes do Baker não são benchmarks de renderização.

## Riscos e ordem de trabalho
P0: provar compute→contador→indirect draw com captura RenderDoc/Vulkan e comparação culling ligado/desligado; confirmar barreiras e ownership. P1: integrar renderer nativo Godot Forward+ com PBR/sombras e demonstrar carregamento do módulo; verificar transições DAG/LOD sem buracos. P2: streaming, paginação e orçamento VRAM. P3: Hi-Z, Visibility Buffer, Material Resolve e rasterização híbrida. Preservar arquitetura existente enquanto os testes determinam falhas reais.

## Reproduzir
`cd D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL` e `python tests/test_suite.py`. Para inicialização headless, usar caminho absoluto do executável Godot 4.7.2 com `--headless --path project --quit`; este teste não valida Vulkan gráfico. Executar comparativo A/B/C/D em mesma GPU, câmera, resolução, iluminação e geometria, registrando capturas e contadores GPU.

## Evidências e pendências
`testes_log.txt` documenta a suíte atual; código/shaders e fixture pequena estão no ZIP. Relatórios/imagens `AUDITORIA_FASE3_FINAL` são históricos. Pendem execução Vulkan gráfica, validação do módulo nativo, medição GPU/CPU/VRAM, streaming e provas de continuidade visual.


## Capturas gráficas adicionais (21/10/2026, 16:54)
Quatro PNGs produzidos pelo script `project/scripts/test_negative_probe.gd` existem na raiz e têm timestamp 16:54:19. Inspeção independente por Pillow: todos 1280×720; referência visível (`diag_frame2_ref_visible.png`) tem 2 cores; referência oculta (`diag_frame3_ref_hidden.png`) e frame seguinte (`diag_frame4.png`) têm 1 cor cada e são idênticos pixel a pixel. Captura imediatamente após `pipeline.render_to_viewport` (`diag_frame3_after_arboria.png`) tem 1808 cores e difere da imagem com referência oculta no retângulo x=349..930, y=95..624. Isso é evidência de escrita visual transitória no viewport durante a chamada, mas **não comprova** apresentação persistente no frame seguinte, correção geométrica, culling GPU, execução Vulkan validada, sincronização ou ganho de desempenho. O desenho não persiste no frame 4, segundo a comparação de imagens. Atribuição causal completa exige log de execução associado à captura e instrumentação de GPU.

### Evidência adicional — ciclo de vida do desenho no Viewport (21/10/2026)
Inspeção estática de `project/scripts/vg_gpu_pipeline.gd:924-1004`: `render_to_viewport()` obtém a textura do Viewport por `RenderingServer.texture_get_rd_texture`, cria framebuffer com essa textura e depth próprio (`_recreate_viewport_framebuffer`) e executa `rd.draw_list_draw_indirect(...counter_buf...)` diretamente. Não foi localizada nessa função uma integração por callback de renderização do RenderingServer que garanta ordem após o passe convencional do Godot. Isso é uma **hipótese técnica verificável** para o resultado transitório capturado (frame após chamada muda; frame seguinte volta ao baseline), não prova causal: o renderizador do Godot pode sobrescrever a textura em passes subsequentes. `execute_indirect_draw()` (893-922) também consome o contador indireto, mas usa framebuffer próprio. O `poll_stats_async()` (645-663) usa leitura assíncrona e não comprova, sozinho, ausência de sincronizações bloqueantes em outros caminhos. Exigir captura persistente em frames sucessivos, logs Vulkan validation layers e prova do momento de submissão para concluir integração real.

### Retificação da hipótese de ausência de callback (21/10/2026)
A inspeção ampliada revelou que **existe** conexão explícita ao `RenderingServer.frame_post_draw` em `project/scripts/main_viewer.gd:60` e chamada a `gpu_pipeline.render_to_viewport` em `main_viewer.gd:320`. Os testes `test_m2_indirect_integration.gd`, `test_m3_gpu_main_renderer.gd`, `test_m4_shader_correction.gd` e `test_m5_visual_validation.gd` também utilizam esse callback. Portanto, a hipótese anterior de *ausência de callback* não se sustenta e fica RETIFICADA. Continua não demonstrado que desenhar na textura RD do Viewport durante `frame_post_draw` seja uma integração persistente e suportada em todas as etapas do renderizador. A captura transitória permanece evidência de comportamento visual não persistente no teste negativo específico; a causa exata exige validação instrumental.
