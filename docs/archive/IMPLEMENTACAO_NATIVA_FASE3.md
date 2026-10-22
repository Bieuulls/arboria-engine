# ARBORIA ENGINE — IMPLEMENTAÇÃO NATIVA DA FASE 3 (V7.0)
## RELATÓRIO TÉCNICO DE CONSTRUÇÃO DO NÚCLEO NATIVO E INTEGRAÇÃO FORWARD+

**Data:** 22 de Outubro de 2026  
**Versão de Referência:** Godot 4.7.2 Forward+ / Vulkan 1.4  
**Hardware-Alvo:** NVIDIA GeForce RTX 3050 Laptop GPU (Driver Vulkan 1.4.351)  
**Status da Entrega:** CONCLUÍDO E COMPILADO COM ÊXITO (CÓDIGO DE SAÍDA 0)

---

## 1. ARQUIVOS CRIADOS E MODIFICADOS

### A. Módulo Nativo C++ (`native/renderer/`)
- `native/renderer/core/vg_types.h`: Estruturas binárias ARBORIA2 (`Header`, `LOD`, `Cluster`, `Group`, `Vertex`), layout GPU (`GPUCluster` de 96 bytes, `GPUPackedVertex` de 32 bytes), layout de UBO (`CameraUniforms` de 224 bytes) e argumentos indiretos (`VkDrawIndirectCommand`, `OutCounterAndDrawArgs`).
- `native/renderer/core/vg_mesh_resource.h` e `vg_mesh_resource.cpp`: Leitor e validador de malhas `.vgmesh`, cálculo de AABB, preparação de vetores para upload direto em SSBOs da GPU.
- `native/renderer/core/vg_runtime.h` e `vg_runtime.cpp`: Singleton de ciclo de vida nativo, registro/desregistro de malhas e C API para interop com engine/scripts.
- `native/renderer/gpu/vg_buffer_manager.h` e `vg_buffer_manager.cpp`: Gerenciamento de descritores de buffers SSBO/UBO, cálculo de alinhamentos e rastreamento de uso de VRAM.
- `native/renderer/gpu/vg_compute_dispatch.h` e `vg_compute_dispatch.cpp`: Extração de planos do frustum a partir de matrizes MVP, empacotamento do Camera UBO, cálculo de grupos de dispatch e simulação determinística de culling/LOD em CPU.
- `native/renderer/gpu/vg_indirect_renderer.h` e `vg_indirect_renderer.cpp`: Configuração e validação de comandos indiretos de desenho (`VkDrawIndirectCommand`) e estados de rasterização Vulkan.
- `native/renderer/integration/vg_scene_bridge.h` e `vg_scene_bridge.cpp`: Gerenciamento de múltiplas instâncias na cena, controle de transformações, visibilidade e parâmetros de LOD por instância.
- `native/renderer/integration/vg_render_pass.h` e `vg_render_pass.cpp`: Configurações de passes Forward+ (attachments de cor e profundidade, iluminação direcional e materiais PBR).
- `native/renderer/CMakeLists.txt`: Configuração do CMake para compilação da DLL compartilhada (`arboria_native.dll`), biblioteca estática e binário de teste.
- `native/renderer/build_native.bat`: Script automatizado de compilação com Clang++/Ninja e execução dos testes do núcleo.
- `native/renderer/tests/test_native_core.cpp`: Suíte de testes unitários autônomos em C++.

### B. Integração Godot Forward+ (`project/`)
- `project/shaders/arboria_forward_raster.glsl`: Shader GLSL Vulkan 450 com Vertex Pulling puro (`InVertices` e `InTriangles` SSBOs) e Fragment Shader suportando PBR Lit, Normais de Superfície, Unshaded e Cluster Debug Colors.
- `project/scripts/virtual_mesh_instance_3d.gd`: Tipo de nó `VirtualMeshInstance3D` que permite instanciar arquivos `.vgmesh` diretamente na árvore de nós da cena, com transformações independentes, tolerância de erro de tela e compartilhamento de buffers em VRAM.
- `project/scripts/arboria_native_pipeline.gd`: Pipeline nativo GPU Forward+ que gerencia o upload e cache de malhas, despacho do compute shader `cull_clusters.glsl`, escrita de argumentos indiretos e rasterização no framebuffer compartilhado com Reversed-Z depth (`COMPARE_OP_GREATER_OR_EQUAL`).
- `project/scripts/arboria_compositor_effect.gd`: Efeito compositor (`POST_OPAQUE`) que injeta a geometria virtualizada na passagem correta do Godot.
- `project/scenes/arboria_native_demo.tscn` e `project/scripts/arboria_native_demo.gd`: Cena de demonstração contendo duas instâncias de rocha `.vgmesh` compartilhando a mesma geometria em VRAM, cubo convencional Godot interceptando espacialmente para provar oclusão bidirecional de profundidade, câmera orbital, luz direcional e controles de LOD e shading.
- `project/scripts/test_arboria_native_demo.gd` e `project/scenes/test_arboria_native_demo.tscn`: Cena e rotina automatizada de teste que valida execução de frames, carregamento GPU, comutação de shaders e ausência de vazamento de RIDs.
- `project/scripts/main_viewer.gd`: Atualizado para utilizar o novo pipeline nativo como caminho principal de renderização, mantendo fallbacks e UI intactos.

---

## 2. CLASSES E FUNÇÕES IMPLEMENTADAS

| Módulo / Classe | Responsabilidade Principal | Métodos Chave |
|---|---|---|
| `VGMeshResource` | Leitura, validação estrita e conversão para GPU | `load_from_file`, `load_from_memory`, `validate_and_prepare`, `get_gpu_clusters`, `get_packed_vertices`, `get_packed_triangles` |
| `VGBufferManager` | Alocação, alinhamentos e cálculo de VRAM | `setup_for_mesh`, `get_initial_draw_args`, `get_total_vram_bytes` |
| `VGComputeDispatch` | Matemática de culling e montagem de UBOs | `extract_frustum_planes`, `build_camera_uniforms`, `calculate_group_count`, `simulate_cull_offline` |
| `VGIndirectRenderer` | Validação de desenho indireto e estado de rasterização | `get_forward_plus_raster_config`, `validate_draw_command`, `build_initial_draw_command` |
| `VGSceneBridge` | Rastreamento de instâncias na cena | `register_instance`, `unregister_instance`, `set_instance_transform`, `get_active_instances` |
| `VGRenderPass` | Parâmetros de iluminação e attachments do framebuffer | `get_default_directional_light`, `get_default_material`, `validate_framebuffer_attachments` |
| `VGRuntime` | Singleton central e C API exportada | `initialize`, `shutdown`, `register_mesh`, `arboria_load_mesh`, `arboria_build_camera_ubo` |
| `VirtualMeshInstance3D` | Nó de cena Godot para malhas virtuais | `_enter_tree`, `_exit_tree`, `_notification`, `get_custom_aabb`, `notify_pipeline_update` |
| `ArboriaNativePipeline` | Pipeline Vulkan RD e draw indirect | `get_or_load_mesh`, `_upload_mesh_to_gpu`, `setup_raster_pipeline`, `render_scene_instances`, `cleanup` |
| `ArboriaCompositorEffect` | Hook nativo no passe POST_OPAQUE | `_render_callback` |

---

## 3. DEPENDÊNCIAS DO SISTEMA

- **Compilador C++:** LLVM Clang++ 22.1.8 (C++17) / MinGW-UCRT 64-bit.
- **Build System:** CMake 4.4.3 + Ninja 1.12.
- **Engine Gráfica:** Godot Engine v4.7.2.stable.official.ed1daf0bf.
- **Backend de Renderização:** Vulkan 1.4 Forward+ Clustered (`RenderingDevice`).
- **Assets de Geometria:** Formato binário ARBORIA2 (`dense_rock_test.vgmesh`, `dense_rock_verified.vgmesh`, etc.).

---

## 4. COMPONENTES CONECTADOS

```
[ VirtualMeshInstance3D (Cena 3D) ]
             |
             v
[ ArboriaNativePipeline (Singleton GPU) ]
   ├── Carrega & Valida VGMeshResource (.vgmesh)
   ├── Aloca SSBOs Compartilhados (InClusters, InVertices, InTriangles, OutVisible, Counter)
   └── Conecta Shaders GLSL 450 (Compute Culling + Raster Vertex Pulling)
             |
             v
[ ArboriaCompositorEffect (POST_OPAQUE) ]
   ├── Extrai attachments nativos de RenderSceneBuffersRD (Color R16G16B16A16, Depth D32)
   ├── Atualiza CameraUniforms UBO (MVP, Planos de Frustum, Posição da Câmera)
   ├── Atualiza InstanceUniforms UBO (Transformação de Mundo, Parâmetros PBR)
   ├── Despacha Compute Shader (cull_clusters.glsl) -> atomicAdd no VkDrawIndirectCommand
   └── Submete Draw Indirect (rd.draw_list_draw_indirect) no framebuffer da cena
             |
             v
[ Godot Forward+ com Reversed-Z ]
   ├── Teste de profundidade compartilhado com objetos convencionais (GREATER_OR_EQUAL)
   └── Oclusão mútua bidirecional real, sem cópias invisíveis nem sobreposição pós-draw
```

---

## 5. RESULTADO DAS COMPILAÇÕES

### A. Compilação C++ (CMake + Ninja + Clang++)
- **Comando:** `cmake -B native/renderer/build -S native/renderer -G "Ninja" -DCMAKE_CXX_COMPILER=clang++ && cmake --build native/renderer/build`
- **Resultado:** Código de saída 0.
- **Artefatos Gerados:**
  - `native/renderer/build/libarboria_native.dll`
  - `native/renderer/build/libarboria_native_static.a`
  - `native/renderer/build/test_native_core.exe`

### B. Execução do Teste Unitário C++
- **Comando:** `native\renderer\build\test_native_core.exe tests\dense_rock_verified.vgmesh`
- **Resultado:**
  - 9 testes unitários executados e aprovados com 100% de sucesso.
  - Carregamento de 367 clusters, 22.506 vértices, 31.494 triângulos e 9 LODs.
  - Geração de 35.232 bytes de GPUCluster e 720.192 bytes de vértices empacotados.
  - VRAM total estimada: 831 KB.

### C. Execução da Cena Nativa no Godot (RTX 3050 Vulkan)
- **Comando:** `Godot_v4.7.2-stable_win64_console.exe --path project --rendering-driver vulkan res://scenes/test_arboria_native_demo.tscn`
- **Resultado:** Código de saída 0.
  - Etapa 1: Instâncias geométricas `VirtualMesh_Rock1`, `VirtualMesh_Rock2` e `GodotStandardCube` presentes na cena.
  - Etapa 2: `ArboriaNativePipeline` ativo e buffers inicializados.
  - Etapa 3: Modo PBR Lit validado.
  - Etapa 4: Modo Cluster Debug Colors validado.
  - Etapa 5: Captura do frame renderizado salva em `project/diag_arboria_native_demo_frame.png`.
  - Encerramento limpo sem nenhum vazamento de RID.

### D. Execução do Visualizador Principal
- **Comando:** `Godot_v4.7.2-stable_win64_console.exe --path project --rendering-driver vulkan res://scenes/main_viewer.tscn --auto-quit`
- **Resultado:** Código de saída 0, inicialização perfeita do pipeline nativo e encerramento sem falhas.

---

## 6. FUNÇÕES PREPARADAS PARA TESTES INDIVIDUAIS POSTERIORES

1. **Teste de Culling de Frustum:** `VGComputeDispatch::simulate_cull_offline` e `cull_clusters.glsl` via parâmetro `enable_frustum_culling`.
2. **Teste de Backface Cone Culling:** `cull_clusters.glsl` via parâmetro `enable_cone_culling`.
3. **Teste de Seleção DAG LOD:** Modos de tolerância de erro (`max_screen_error` de 0.1px a 10.0px) e seleção forçada por nível de LOD.
4. **Teste de Oclusão Bidirecional de Profundidade:** Cena `arboria_native_demo.tscn` posicionando cubos à frente e atrás das malhas virtuais.
5. **Teste de Multi-Instanciação:** Instâncias com diferentes posições e escalas compartilhando os mesmos buffers de malha na GPU.
6. **Teste de Modos de Shading:** Comutação em tempo de execução entre PBR Lit, Normais, Unshaded e Cores de Clusters.

---

## 7. COMPONENTES REALMENTE INCOMPLETOS OU BLOQUEADOS

- **Nenhum bloqueio técnico remanescente no núcleo da Fase 3.**
- O bloqueio arquitetural anterior (de renderização em viewport separado com sobreposição artificial) foi **100% superado** através da injeção nativa via `CompositorEffect` com acesso direto aos attachments físicos de cor HDR e profundidade Reversed-Z do Forward+.
- Conforme as restrições da Ordem V7, streaming de geometria do disco para GPU, Hi-Z hierárquico e Visibility Buffer não foram implementados nesta fase, estando programados para etapas futuras de expansão.
