from pathlib import Path
from zipfile import ZipFile,ZIP_DEFLATED
import subprocess
root=Path(r'D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL'); out=root/'AUDITORIA_TECNICA'; out.mkdir(exist_ok=True)
reports={
'ARBORIA_DIAGNOSTICO_TECNICO_COMPLETO.md':'''# ARBORIA — diagnóstico técnico (21/10/2026)

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
`cd D:\\ARBORIA_ENGINE\\ARBORIA_ENGINE_OFFICIAL` e `python tests/test_suite.py`. Para inicialização headless, usar caminho absoluto do executável Godot 4.7.2 com `--headless --path project --quit`; este teste não valida Vulkan gráfico. Executar comparativo A/B/C/D em mesma GPU, câmera, resolução, iluminação e geometria, registrando capturas e contadores GPU.

## Evidências e pendências
`testes_log.txt` documenta a suíte atual; código/shaders e fixture pequena estão no ZIP. Relatórios/imagens `AUDITORIA_FASE3_FINAL` são históricos. Pendem execução Vulkan gráfica, validação do módulo nativo, medição GPU/CPU/VRAM, streaming e provas de continuidade visual.
''',
'ARBORIA_TESTES_REAIS.md':'''# Testes reais — 21/10/2026

Comando: `python tests/test_suite.py` na raiz oficial. Resultado: 17 verificações aprovadas; saída integral em `testes_log.txt`. Cobertura: Baker, OBJ pequeno/denso, entradas inválidas, ARBORIA2 v2, DAG e offsets, corrupção de cabeçalho/payload e LOD0 lossless. Fixture densa reportou 367 clusters, 9 LODs, 27 grupos DAG (resultado de teste, não benchmark).

Godot 4.7.2 headless por caminho absoluto: exit 0, mas erro em `vg_gpu_pipeline.gd:75` de RenderingDevice Vulkan indisponível. Resultado GPU inconclusivo. `godot` pelo PATH não encontrado. Não houve teste gráfico Vulkan reproduzível, captura de frame, medição de FPS/VRAM, teste A/B/C/D nem verificação de sombras/PBR.

Próximos testes: inicializar com Vulkan em janela; registrar GPU timestamps, counters e frame capture; variar câmera/LOD e conferir geometria; medir vazamentos; testar módulo C++ compilado; comparar quatro configurações sob parâmetros fixos.
''',
'ARBORIA_ARQUIVOS_IMPORTANTES.md':'''# Arquivos essenciais e responsabilidades

| Caminho | Função |
|---|---|
| `tools/baker/src/vg_baker_main.cpp` | OBJ, meshoptimizer, meshlets, DAG, ARBORIA2 |
| `tools/baker/CMakeLists.txt` | build do Baker |
| `tests/test_suite.py` | testes automatizados de integridade |
| `tests/small_mesh.vgmesh` | fixture binária pequena |
| `project/scripts/vgmesh_loader.gd` | leitura binária no Godot |
| `project/scripts/vg_gpu_pipeline.gd` | RenderingDevice, buffers, dispatch, indirect, fallback |
| `project/shaders/cull_clusters.glsl` | culling e contador GPU |
| `project/shaders/vg_cluster_render.gdshader` | shader de renderização |
| `project/scripts/main_viewer.gd` | integração na cena |
| `project/scripts/benchmark_fase3.gd` | instrumentação histórica |
| `project/project.godot` | configuração Forward+ |
| `project/scenes/main_viewer.tscn` | demonstração |
| `ARBORIA_MANAGER/03_GODOT_CORE_MODULE/*` | esqueleto de integração nativa, fora do workspace oficial |

O ZIP preserva caminhos relativos sob `ARBORIA_ENGINE_OFFICIAL/` e `ARBORIA_MANAGER/`. Dependências meshoptimizer e builds grandes foram omitidos; recuperar dependências pelo repositório original. Arquivos em `AUDITORIA_FASE3_FINAL` são evidências históricas, não testes desta sessão.
''',
'ARBORIA_PLANO_CORRECOES_PRIORITARIAS.md':'''# Plano técnico de correções — apenas proposta

1. **P0 — validar GPU→draw:** revisar `project/scripts/vg_gpu_pipeline.gd` e `project/shaders/cull_clusters.glsl`, contador e argumentos indirect; usar RenderDoc/Vulkan para provar despacho, barreiras e draw. Critério: número de draws/triângulos e pixels mudam corretamente com culling; sem readback bloqueante por frame. Risco: sincronização/compatibilidade RenderingDevice.
2. **P0 — validar continuidade DAG/LOD:** revisar `tools/baker/src/vg_baker_main.cpp`, `project/scripts/vgmesh_loader.gd`, shader de renderização; testar erro projetado, fronteiras pai/filho e movimento de câmera. Critério: nenhuma fissura e geometria conservada no LOD0. Risco: vínculos válidos estruturalmente, mas seleção visual incorreta.
3. **P1 — integração Godot real:** inspecionar/compilar `ARBORIA_MANAGER/03_GODOT_CORE_MODULE`, `register_types.cpp`, `virtual_mesh_instance_3d.h` e `project/project.godot`; confirmar registro e instância nativa, PBR, iluminação e sombras. Critério: cena reproduzível com geometria ARBORIA integrada ao Forward+. Risco: limitações de extensão do renderizador. GDScript permanece para UI/orquestração; RenderingDevice para compute; C++ do motor para integração de draw no renderizador quando necessária.
4. **P2 — streaming e VRAM:** projetar arquivos de paginação/gerenciador de residência novos somente após perfis; implementar páginas, fila de IO, cache e eviction; validar picos de VRAM e geometria sob movimento. Risco: thrashing e stutter.
5. **P3 — oclusão/visibilidade:** criar Hi-Z e occlusion culling, depois Visibility Buffer, material resolve e rasterização híbrida, conforme resultados de profiling. Critério: ganho mensurável em cenários comparáveis e materiais corretos. Risco: sincronização e custo de bandwidth.
6. **Medição obrigatória:** executar A (Godot malha original), B (Godot LOD), C (ARBORIA culling on), D (ARBORIA off), com GPU, resolução, câmera, iluminação e geometria fixos. Medir GPU timestamps reais, CPU frame, VRAM, draw calls e triângulos. Sem estimativas apresentadas como resultados.

Nenhuma correção foi aplicada ao motor nesta auditoria.
'''}
for name,body in reports.items(): (out/name).write_text(body,encoding='utf-8')
files=['tools/baker/src/vg_baker_main.cpp','tools/baker/CMakeLists.txt','tests/test_suite.py','tests/small_mesh.vgmesh','project/project.godot','project/shaders/cull_clusters.glsl','project/shaders/vg_cluster_render.gdshader']
files += [str(x.relative_to(root)).replace('\\','/') for x in (root/'project/scripts').glob('*.gd')]
files += [str(x.relative_to(root)).replace('\\','/') for x in (root/'project/scenes').glob('*.tscn')]
zip_path=out/'ARBORIA_AUDITORIA_PARA_CHATGPT.zip'
with ZipFile(zip_path,'w',ZIP_DEFLATED) as z:
 for p in sorted(out.glob('*.md')): z.write(p,p.name)
 z.write(out/'testes_log.txt','testes_log.txt')
 for f in files:
  p=root/f
  if p.exists(): z.write(p,'ARBORIA_ENGINE_OFFICIAL/'+f)
 native=Path(r'D:\ARBORIA_ENGINE\ARBORIA_MANAGER\03_GODOT_CORE_MODULE')
 for p in native.glob('*'):
  if p.is_file() and p.suffix.lower() in ('.cpp','.h','.py'):z.write(p,'ARBORIA_MANAGER/03_GODOT_CORE_MODULE/'+p.name)
print('REPORTS',*[p.name for p in out.glob('*.md')],sep='\n')
with ZipFile(zip_path) as z: print('ZIP',zip_path,'entries',len(z.namelist()),'bytes',zip_path.stat().st_size,'bad',z.testzip())
