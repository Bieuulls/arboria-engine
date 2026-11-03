# ARBORIA ENGINE — Enterprise Readiness Assessment

**Data:** 2026-11-01  
**Status do projeto:** Stages 0–2 concluídos, Stage 03 em andamento  
**Objetivo:** Elevar o ARBORIA ENGINE a nível enterprise / ultra games (produção AAA)

---

## 1. Resumo Executivo

O ARBORIA ENGINE é um addon de geometria virtualizada (Nanite-like DAG) para Godot 4.7+ com backend C++ via GDExtension, renderização GPU-driven (culling + draw indireto), Hi-Z occlusion culling, pipeline Forward+/Vulkan 1.4, integração com Jolt Physics e importação automática de modelos `.obj/.gltf/.glb` para `.vgmesh`.

**Resultado atual:** A arquitetura base está funcional e validada (99.95% de redução de draw calls, 150x de speedup teórico na submissão GPU). No entanto, há um **gargalo crítico de CPU (7.01 ms)** na submissão via GDScript/RenderingDevice que invalida a vantagem de GPU em cenas densas — decisão técnica registrada como **NO-GO** para substituição automática do renderizador nativo.

**Para atingir nível enterprise/ultra games**, são necessárias melhorias em 14 áreas técnicas (Stages 03–14) mais 8 áreas de infraestrutura enterprise (CI/CD, multi-plataforma, documentação, testes, ferramentas, etc.).

---

## 2. Matriz de Avaliação: Estado Atual vs. Requisito Enterprise

| Área | Estado Atual | Requisito Enterprise | Status | Prioridade |
|------|-------------|---------------------|--------|------------|
| Renderização GPU-driven | Culling + draw indireto implementado | Submissão zero-CPU, ring buffers, partial updates | ⚠️ Parcial | Crítica |
| Hi-Z Occlusion Culling | Pirâmide implementada com workaround de textura | Implementação completa Reversed-Z + mip chain | ⚠️ Parcial | Alta |
| DAG / LOD contínuo | Traversal hierárquico top-down | Geometric continuity, morfo entre LODs | ⚠️ Parcial | Alta |
| PBR / Materiais | Cook-Torrance GGX, ACES, texturas PBR | Materiais avançados, subsurface, anisotrópico | ⚠️ Parcial | Média |
| Física Jolt | Collision shapes desacopladas, estático/rigid | Soft bodies, destructível, nave mesh | ❌ Ausente | Média |
| Streaming VRAM | LRU eviction, página residency, orçamento 2MB testado | VGPageTable, resident manager, fallback clusters | ⚠️ Parcial | Alta |
| Import/Editor | Auto-import .obj/.gltf/.glb, dock, visualizador de clusters | LOD baking presets, remesh, atlas, procedural | ⚠️ Parcial | Média |
| Benchmark | 1000 frames, Vulkan timestamps, ci_local.bat | Suite reprodutível, CI, regressão automática | ⚠️ Parcial | Alta |
| Stress test | Não executado | 20 min, cenários extremos, leak detection | ❌ Ausente | Alta |
| Refactoring | Código funcional, GDScript/C++ misto | Limpeza, padronização, tipos estritos | ❌ Ausente | Média |
| CI/CD | ci_local.bat local | GitHub Actions, multi-plataforma, release pipeline | ❌ Ausente | Crítica |
| Multi-plataforma | Windows/Linux (Vulkan) | macOS, consoles, Vulkan/Metal/DX12 | ❌ Ausente | Alta |
| Ray tracing | Não implementado | RTX reflections, GI, sombras ray-traced | ❌ Ausente | Baixa |
| Animação/Skinning | Não suportado | Skeletal animation, morph targets | ❌ Ausente | Alta |
| Terrain/Foliage | Não implementado | World partition, instancing massivo | ❌ Ausente | Média |
| Multi-GPU | Não implementado | SLI/CrossFrame, split-frame rendering | ❌ Ausente | Baixa |

---

## 3. Stages Restantes (03–14) — Detalhamento e Priorização

### Stage 03: Remover CPU/GPU Blockers, Refinar Buffer Management
**Objetivo:** Eliminar o gargalo de CPU (7.01 ms) na submissão de instâncias.

**Tarefas:**
- [ ] Implementar ring buffers para dados de instância (evitar realloc por frame)
- [ ] Partial updates: atualizar apenas instâncias dirty (transform/LOD mudou)
- [ ] Reusable pools de buffers GPU (sem alocação/free por frame)
- [ ] Eliminar sync readbacks síncronos (buffer_get_data) — usar async telemetry já existente
- [ ] Mover submissão de buffers do GDScript para C++ nativo (via GDExtension direto)
- [ ] Double/triple buffering de command buffers para sobrepor CPU/GPU

**Critério de sucesso:** CPU render ≤ 0.5 ms em 500 instâncias dense_rock.

**Dependências:** Nenhuma (pode começar imediatamente).

---

### Stage 04: Depth/Forward+ Integration Verification
**Objetivo:** Verificar Reversed-Z, sombras e oclusão mútua no pipeline Forward+.

**Tarefas:**
- [ ] Verificar Reversed-Z consistente em depth prepass + main raster
- [ ] Integrar sombra direcional (Shadow Atlas + CSM do Godot) com shadow proxy
- [ ] Oclusão mútua entre instâncias via Hi-Z (instância A oclui instância B)
- [ ] Verificar transparência e alpha scissor no pipeline de clusters
- [ ] Testar múltiplas câmeras (split-screen, reflexos)

**Critério de sucesso:** Zero artefatos visuais em cenas com sombras + oclusão mútua.

**Dependências:** Stage 03 (buffers estáveis), Stage 05 (Hi-Z real).

---

### Stage 05: Hierarchical Z-Buffer Real Implementation
**Objetivo:** Implementar Hi-Z completo, conservador, com mip chain gerada na GPU.

**Tarefas:**
- [ ] Substituir workaround de texture_copy() por geração real de mip chain em compute shader
- [ ] Hi-Z culling conservador (teste de caixa delimitadora contra pirâmide)
- [ ] Early-Z rejection no rasterizador de clusters
- [ ] Hi-Z resolução adaptativa baseada no tamanho da tela
- [ ] Debug visualizador de pirâmide Hi-Z no editor

**Critério de sucesso:** Redução adicional de ≥30% em fragments rasterizados vs. baseline.

**Dependências:** Stage 04 (depth integration).

---

### Stage 06: DAG Refinement and Geometric Continuity
**Objetivo:** Eliminar popping visual entre LODs, garantir continuidade geométrica.

**Tarefas:**
- [ ] Implementar morphing entre níveis de LOD (interpolação de vértices)
- [ ] Verificar corte monótono do DAG (sem clusters duplicados ou perdidos)
- [ ] Métrica de erro tela-espaço refinada (screen-space error com tamanho de pixel)
- [ ] Histerese de LOD (evitar flickering entre níveis adjacentes)
- [ ] Fallback clusters para LOD mais baixo quando stream não completo

**Critério de sucesso:** Zero popping visível em câmera em movimento, DAG monotonic cut verificado.

**Dependências:** Nenhuma crítica (independente).

---

### Stage 07: PBR Materials and Attribute Integrity
**Objetivo:** Garantir integridade de atributos (normais, UVs, tangentes) e materiais PBR robustos.

**Tarefas:**
- [ ] Verificar unpacking de normais/tangentes no vertex shader (compressed attributes)
- [ ] Suporte a normal mapping, ORM (occlusion-roughness-metallic), emissivo
- [ ] Subsurface scattering para materiais orgânicos (pedra, pele, cera)
- [ ] Anisotropic roughness para metais escovados
- [ ] Clear coat para materiais automotivos/plásticos
- [ ] Validação de integridade: atributos não corrompidos após culling/LOD

**Critério de sucesso:** Materiais PBR idênticos ao Godot StandardMaterial3D em todas as condições de iluminação.

**Dependências:** Nenhuma crítica.

---

### Stage 08: Virtual Memory System (VGPageTable, GeometryPage, Residency Manager)
**Objetivo:** Sistema de memória virtual para geometria, streaming sob demanda.

**Tarefas:**
- [ ] Implementar VGPageTable (mapeamento virtual → físico de páginas de geometria)
- [ ] GeometryPage: unidade de streaming (cluster ou grupo de clusters)
- [ ] Residency manager: decidir o que fica residente vs. evictado
- [ ] Page fault handler: carregar página faltante de forma assíncrona
- [ ] Fallback clusters: LOD de baixa resolução quando página não residente
- [ ] Coherência de página entre frames (evitar thrashing)

**Critério de sucesso:** Orçamento VRAM respeitado 100% do tempo, page faults < 1% dos frames.

**Dependências:** Stage 03 (buffer management), Stage 09 (streaming integration).

---

### Stage 09: Streaming Integration with DAG/Renderer
**Objetivo:** Integrar streaming de geometria com DAG e renderizador.

**Tarefas:**
- [ ] Conectar streaming_update() (posição da câmera) ao residency manager
- [ ] Prefetch: carregar páginas antes de ficarem visíveis (baseado em vetor de câmera)
- [ ] Eviction policy: LRU + prioridade por distância à câmera
- [ ] Sincronizar LOD selecionado com páginas residentes (não renderizar LOD não residente)
- [ ] Streaming assíncrono sem travar a thread principal

**Critério de sucesso:** Câmera movendo-se rapidamente sem pausas visíveis (stutter).

**Dependências:** Stage 08 (virtual memory).

---

### Stage 10: Professional Import/Editor Workflow
**Objetivo:** Fluxo de trabalho profissional no editor Godot.

**Tarefas:**
- [ ] Presets de importação (game, archviz, cinematic) com parâmetros otimizados
- [ ] Remesh automático para clusters ótimos (128 triangles, 256 vértices)
- [ ] UV atlas automático para lightmaps
- [ ] Visualizador de clusters no editor com modo wireframe/solid/hybrid
- [ ] Inspector de LOD: ver seleção de LOD por cluster em tempo real
- [ ] Batch import de múltiplos modelos com configuração em lote
- [ ] Validação de malha de entrada (manifold, normais, UVs sobrepostos)

**Critério de sucesso:** Import de modelo complexo (>1M triângulos) em < 30s com clusters válidos.

**Dependências:** Nenhuma crítica.

---

### Stage 11: Real Reproducible Benchmark Suite
**Objetivo:** Suíte de benchmark automatizada, reprodutível, para CI.

**Tarefas:**
- [ ] Cenários padronizados: sparse (1 instância), dense (500), ultra-dense (5000)
- [ ] Métricas: frame time p95/p99, CPU render, GPU render, VRAM, draw calls, tris
- [ ] Execução determinística (mesma semente, mesma cena, mesma resolução)
- [ ] Detecção de regressão automática (threshold de ±5% vs. baseline)
- [ ] Relatório HTML/JSON com comparação histórica
- [ ] Integração com ci_local.bat e CI remoto

**Critério de sucesso:** Suite roda em CI sem intervenção humana, detecta regressões.

**Dependências:** Nenhuma crítica.

---

### Stage 12: 20-Minute Stress Test
**Objetivo:** Validar estabilidade em sessão longa, detecção de memory leaks.

**Tarefas:**
- [ ] Teste de 20 minutos contínuos com câmera em movimento aleatório
- [ ] Detecção de vazamento de VRAM (resident bytes deve se estabilizar)
- [ ] Detecção de vazamento de handles (geracionais não vazam)
- [ ] Teste de estresse: 10.000+ instâncias, cena com todos os materiais
- [ ] Teste de estresse: câmera atravessando geometria (oclusão total/parcial)
- [ ] Relatório de estabilidade com métricas ao longo do tempo

**Critério de sucesso:** Zero crashes, zero memory leaks, frame time estável (variação < 10%).

**Dependências:** Stage 03, Stage 08, Stage 09.

---

### Stage 13: Controlled Technical Refactoring
**Objetivo:** Limpar código, padronizar, preparar para release.

**Tarefas:**
- [ ] Unificar API: GDScript vs. C++ (remover duplicação de métodos de compatibilidade)
- [ ] Tipagem estrita em GDScript (todos os arquivos com tipagem completa)
- [ ] Remover código morto e comentários obsoletos
- [ ] Padronizar nomenclatura (português/inglês — escolher um idioma único)
- [ ] Documentação inline (docstrings em todas as funções públicas)
- [ ] Separação clara: core engine vs. Godot integration layer

**Critério de sucesso:** Código passa em linter, sem warnings, documentação 100% da API pública.

**Dependências:** Todos os stages anteriores (refatorar após funcionalidades estarem estáveis).

---

### Stage 14: Release Candidate arboria-rc1
**Objetivo:** Preparar versão candidata a release estável.

**Tarefas:**
- [ ] Versionamento semântico (v1.0.0-rc1)
- [ ] Changelog completo
- [ ] Notas de compatibilidade (Godot 4.7+, Vulkan 1.2+, Jolt Physics)
- [ ] Pacote de distribuição (addon pronto para instalar)
- [ ] Exemplo de cena de produção (demo scene)
- [ ] Guia de migração para usuários do renderizador nativo Godot

**Critério de sucesso:** RC1 instalável e funcional em projeto de teste externo.

**Dependências:** Todos os stages 03–13.

---

## 4. Enterprise Gaps — Infraestrutura e Operações

### 4.1 CI/CD (Crítica)
**Ausente.** Atualmente só existe `ci_local.bat` (local, Windows).

**Necessário:**
- GitHub Actions: build C++ (Windows + Linux), testes Godot headless, benchmark regressão
- Multi-plataforma: Windows, Linux, macOS (quando suportado)
- Release pipeline: tag → build → pacote addon → release no GitHub
- Code quality: lint GDScript, linter C++ (clang-tidy), cobertura de testes

### 4.2 Multi-Plataforma (Alta)
**Atual:** Windows 10/11 + Linux x86_64, Vulkan 1.2+.

**Necessário:**
- macOS (Metal backend — requer renderizador separado ou translayer)
- Consoles (PlayStation, Xbox — requer NDAs e SDKs proprietários)
- Vulkan/Metal/DX12 abstraction layer no backend C++
- Testes em hardware variado (RTX 3050 baseline, RTX 4090, AMD RX, Intel Arc)

### 4.3 Ray Tracing (Baixa)
**Ausente.**

**Necessário (opcional, futuro):**
- Refletos ray-traced (RTX)
- Iluminação global (GI) via path tracing
- Sombras ray-traced para área lights
- Integração com Vulkan Ray Tracing pipelines

### 4.4 Animação e Skinning (Alta)
**Ausente.** Apenas malhas estáticas/rigidas.

**Necessário:**
- Skeletal animation (skinned meshes) com LOD
- Morph targets (blend shapes)
- Animação de instâncias (transformação por instância)
- Sincronização animação ↔ culling (box animado deve ser re-culled)

### 4.5 Terrain e Foliage (Média)
**Ausente.**

**Necessário:**
- World partition (divisão do mundo em células)
- Terrain virtualizado (heightmap + LOD)
- Foliage instancing (grama, árvores milhares de instâncias)
- Wind animation para vegetação (já existe no fragment shader, mas limitado)

### 4.6 Materiais Avançados (Média)
**Parcial.** PBR Cook-Torrance GGX básico.

**Necessário:**
- Subsurface scattering
- Anisotropic
- Clear coat
- Sheen (tecidos)
- Decals (projetados)
- Parallax occlusion mapping

### 4.7 Multi-GPU (Baixa)
**Ausente.**

**Necessário (futuro):**
- Split-frame rendering (metade do frame por GPU)
- Alternate frame rendering
- NVLink / Infinity Fabric para compartilhamento de memória

### 4.8 Documentação e Treinamento (Crítica)
**Atual:** README_PT.md, README.md, comentários no código.

**Necessário:**
- Documentação técnica completa (API C++, API GDScript, shaders)
- Guia de integração (como adicionar Arboria a um projeto Godot existente)
- Guia de otimização (quando usar Arboria vs. MeshInstance3D nativo)
- Exemplos de código (snippets para casos comuns)
- Tutoriais em vídeo (opcional, mas recomendado)

### 4.9 Testes Automatizados (Crítica)
**Atual:** 27 testes no painel + CTest C++.

**Necessário:**
- Testes unitários para cada módulo C++ (tipos, runtime, streaming, DAG)
- Testes de integração GDScript → C++
- Testes de regressão visual (screenshots comparados)
- Testes de performance (regras de CI: falhar se regressão > 5%)
- Testes em headless (sem display, para CI)

### 4.10 Segurança e Integridade (Média)
**Parcial.** Já existe engine signature, license hash, verify_engine_integrity.

**Necessário:**
- Assinatura de binários (code signing)
- Verificação de integridade de assets .vgmesh (checksum)
- Sanitização de caminhos de importação (path traversal)
- Sandbox do GDExtension (acesso limitado a sistema de arquivos)

---

## 5. Roadmap de Implementação (12 Semanas)

| Semana | Stage | Foco | Entregável |
|--------|-------|------|------------|
| 1 | Stage 03 | Remover CPU blockers | Ring buffers, partial updates, pools |
| 2 | Stage 03 | Submissão C++ nativa | CPU ≤ 0.5 ms em 500 instâncias |
| 3 | Stage 04-05 | Depth/Forward+ + Hi-Z real | Reversed-Z, sombras, oclusão mútua |
| 4 | Stage 05 | Hi-Z otimizado | Mip chain GPU, early-Z |
| 5 | Stage 06 | DAG refinement | Morphing, histerese, zero popping |
| 6 | Stage 07-08 | PBR + Virtual Memory | VGPageTable, residency, page faults |
| 7 | Stage 09 | Streaming integration | Prefetch, eviction, sem stutter |
| 8 | Stage 10 | Editor workflow | Presets, visualizador, batch import |
| 9 | Stage 11 | Benchmark suite | CI automatizada, detecção de regressão |
| 10 | Stage 12 | Stress test 20 min | Estabilidade, leak detection |
| 11 | Stage 13 | Refactoring | Código limpo, tipagem, documentação |
| 12 | Stage 14 | Release candidate | arboria-rc1, demo scene, docs |

---

## 6. Métricas de Sucesso — Enterprise Ultra Games

| Métrica | Baseline Atual | Alvo Enterprise |
|---------|---------------|-----------------|
| CPU render (500 instâncias) | 7.01 ms | ≤ 0.5 ms |
| GPU render (500 instâncias) | 0.63 ms | ≤ 0.3 ms |
| Frame time p95 (500 instâncias) | 8.06 ms | ≤ 6.0 ms (165 FPS @ 1080p) |
| Draw calls | 1 (indireto) | 1 (mantido) |
| Redução de triângulos | 7.9M → 337K | ≥ 95% redução |
| VRAM orçamento 2MB | under_budget: true | 100% dos cenários |
| Page faults | Não medido | < 1% dos frames |
| Memory leaks (20 min) | Não testado | Zero |
| Crashes (20 min) | Não testado | Zero |
| Regressão de performance | Não automatizada | Detecção < 5% em CI |

---

## 7. Riscos e Mitigações

| Risco | Impacto | Probabilidade | Mitigação |
|-------|---------|---------------|-----------|
| Gargalo GDScript persiste | Alto | Média | Mover submissão para C++ nativo (Stage 03) |
| Hi-Z não reduz fragments | Médio | Média | Validar com benchmark antes de prosseguir (Stage 05) |
| DAG popping visual | Médio | Média | Implementar morphing + histerese (Stage 06) |
| Memory leak em streaming | Alto | Baixa | Stress test 20 min + detecção de leaks (Stage 12) |
| Falta de CI/CD | Alto | Alta | Implementar GitHub Actions (Stage 11) |
| Suporte multi-plataforma limitado | Médio | Alta | Abstração de backend (Vulkan/Metal/DX12) |
| Animação/skinning ausente | Médio | Alta | Roadmap pós-rc1 (versão 1.1+) |

---

## 8. Conclusão e Recomendação

O ARBORIA ENGINE tem uma **base técnica sólida** com arquitetura inovadora (DAG + GPU-driven + Hi-Z). O principal obstáculo para nível enterprise é o **gargalo de CPU na submissão via GDScript**, que deve ser resolvido no Stage 03 movendo a submissão para C++ nativo com ring buffers e partial updates.

**Recomendação:** Executar os Stages 03–14 sequencialmente (12 semanas), com foco inicial em Stage 03 (remover CPU blockers) e Stage 11 (benchmark automatizado) para validar cada melhoria mensuravelmente. Após o rc1, avaliar animação/skinning, terrain/foliage e multi-plataforma para versões 1.1+.

---

*Documento gerado como parte do estudo completo do ARBORIA ENGINE para nível empresarial ultra games.*
