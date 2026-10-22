# ARBORIA ENGINE — RELATÓRIO OFICIAL DE ENTREGA
## MISSÃO 3/6: SUBSTITUIÇÃO DO MULTIMESH COMO CAMINHO PRINCIPAL

**Data de Execução:** 21/10/2026  
**Ambiente de Referência:**
- Godot Engine 4.7.2.stable.official.ed1daf0bf
- Vulkan Forward+ (Driver Vulkan 1.4.351)
- Hardware: NVIDIA GeForce RTX 3050 (Device #0)
- Sistema Operacional: Windows 11

---

## 1. RESUMO EXECUTIVO

A Missão 3/6 exigia fazer o ARBORIA **utilizar exclusivamente o desenho orientado pela GPU como caminho principal**, eliminando a dependência do MultiMesh legado e resolvendo o problema de alocação forçada de `multimesh.instance_count = total_clusters`, preservando o MultiMesh estritamente como fallback de diagnóstico sob demanda.

### O que foi Eliminado do Caminho Principal
1. **Zero instâncias de MultiMesh:** O caminho padrão não aloca nem instancia `MultiMesh` (`instance_count = 0`, nó ausente da cena).
2. **Zero texturas legadas geradas compulsoriamente:** As 3 ImageTextures gigantes de amostragem no Vertex Shader (`vertex_texture`, `index_texture`, `meta_texture`) não são mais criadas no carregamento de `.vgmesh`.
3. **Consumo de VRAM reduzido:** A VRAM alocada no carregamento do modelo Dense Rock caiu de **1.693 KB** para **863 KB** (redução de **49%**).
4. **Vertex Pulling direto via SSBOs:** A geometria é extraída diretamente dos buffers `in_vertices_buf` e `in_triangles_buf` na GPU pelo rasterizador indireto Vulkan.

---

## 2. MODIFICAÇÕES DE CÓDIGO REALIZADAS

### 2.1 Em `project/scripts/vg_gpu_pipeline.gd`

#### A. Isolamento do MultiMesh no Carregamento Principal
No método `load_vgmesh()`, removeu-se a chamada automática a `setup_multimesh()`. Os dados do `.vgmesh` são convertidos diretamente para SSBOs Vulkan:
```gdscript
# 7. Buffers de Geometria Real para Rasterizacao Indireta via SSBO (Caminho Principal)
# 32 bytes por vertice: vec4(pos.xyz, uv.x) + vec4(norm.xyz, uv.y)
var raw_v_bytes = PackedByteArray()
raw_v_bytes.resize(total_vertices * 32)
for vi in range(total_vertices):
    var p0_byte = vi * 32
    var p1_byte = vi * 32 + 16
    var p = vertices[vi]
    var n = normals[vi]
    var uv = uvs[vi]

    raw_v_bytes.encode_float(p0_byte + 0, p.x)
    raw_v_bytes.encode_float(p0_byte + 4, p.y)
    raw_v_bytes.encode_float(p0_byte + 8, p.z)
    raw_v_bytes.encode_float(p0_byte + 12, uv.x)

    raw_v_bytes.encode_float(p1_byte + 0, n.x)
    raw_v_bytes.encode_float(p1_byte + 4, n.y)
    raw_v_bytes.encode_float(p1_byte + 8, n.z)
    raw_v_bytes.encode_float(p1_byte + 12, uv.y)

in_vertices_buf = rd.storage_buffer_create(raw_v_bytes.size(), raw_v_bytes)
in_triangles_buf = rd.storage_buffer_create(tri_padded_size, tri_buf_data)

# Cache dos dados para fallback diagnostico sob demanda
cached_vg_data = vg_data
```

#### B. Implementação do Fallback Diagnóstico Sob Demanda
O MultiMesh só é instanciado e suas texturas alocadas se o usuário expressamente invocar `setup_multimesh_fallback()`:
```gdscript
func setup_multimesh_fallback(p_vg_data: Dictionary = {}) -> MultiMeshInstance3D:
    var data = p_vg_data if not p_vg_data.is_empty() else cached_vg_data
    if data.is_empty():
        return null
    ...
    # Aloca vertex_texture, index_texture, meta_texture e template_mesh sob demanda
    build_template_mesh()
    multimesh = MultiMesh.new()
    multimesh.instance_count = total_clusters
    ...
    multimesh_instance.visible = true
    multimesh_fallback_enabled = true
    return multimesh_instance

func disable_multimesh_fallback() -> void:
    multimesh_fallback_enabled = false
    if multimesh_instance:
        multimesh_instance.visible = false
```

### 2.2 Em `project/scripts/main_viewer.gd` e `main_viewer.tscn`

- **Remoção de vínculo compulsório:** Em `load_selected_model()`, removeu-se a chamada a `gpu_pipeline.setup_multimesh()` e `add_child(gpu_pipeline.multimesh_instance)`.
- **Modos de Renderização Claros na UI:**
  - `GPUPipelineCheck` rotulado como `"GPU Indireto (Principal Vulkan)"` (ativo por padrão).
  - `MultiMeshCheck` rotulado como `"MultiMesh Fallback (Diagnóstico)"` (desativado por padrão).
- **Encaminhamento Estanque:**
  - Quando em modo GPU Indireto: `multimesh_instance` fica desativado/inexistente; `render_to_viewport()` é o único renderizador ativo no frame.
  - Quando o usuário marca MultiMesh Fallback: o MultiMesh é gerado sob demanda para fins de diagnóstico.

---

## 3. PROVAS OBRIGATÓRIAS E MEDIÇÕES REAIS DE HARDWARE

As provas foram executadas através da suíte automatizada `project/scripts/test_m3_gpu_main_renderer.gd` na GPU NVIDIA GeForce RTX 3050.

### 3.1 Prova 1: Ausência do MultiMesh no Caminho Principal
Verificação realizada em runtime imediatamente após carregar o modelo `.vgmesh`:
- `pipeline.multimesh == null`: **CONFIRMADO (`true`)**
- `pipeline.multimesh_instance == null`: **CONFIRMADO (`true`)**
- VRAM alocada: **863 KB** (anteriormente 1.693 KB).

### 3.2 Provas 2 e 3: Comparação Câmera Próxima (5m) vs Câmera Distante (35m)
Métricas medidas diretamente na VRAM do hardware através do buffer `counter_buf` (`VkDrawIndirectCommand`) e timestamps Vulkan:

| Campo do Argumento Indireto / Hardware | Câmera Próxima (5m) | Câmera Distante (35m) | Variação Medida |
|---|---|---|---|
| `vertex_count` (offset 0) | `384` | `384` | Vértices fixos por cluster |
| `instance_count` (offset 4) | **`170`** | **`53`** | **-68.8%** clusters submetidos |
| `first_vertex` (offset 8) | `0` | `0` | Base zero |
| `first_instance` (offset 12) | `0` | `0` | Base zero |
| `total_triangles_drawn` (offset 16) | **`15.607`** | **`4.209`** | **-73.0%** triângulos rasterizados |
| `total_clusters_evaluated` (offset 20) | `367` | `367` | 100% dos clusters avaliados |
| `Tempo de GPU Compute` (timestamps Vulkan) | **`6.14 µs`** | **`7.17 µs`** | Medição real em hardware |
| Tamanho do Framebuffer Salvo | `314.574 bytes` | `21.594 bytes` | Redução visual proporcional |

### 3.3 Prova 4: Teste Negativo (MultiMesh Totalmente Desativado)
- Chamada indireta desativada: `pipeline.set_indirect_draw_enabled(false)`.
- Framebuffer limpo e submetido ao frame do Viewport.
- Resultado: **`230.400 pixels` alterados / apagados**.
- A imagem `03_teste_negativo_desativado.png` resultou em viewport completamente vazio (2.772 bytes).
- **Conclusão:** Nenhum outro componente (nem MultiMesh, nem nós de MeshInstance3D do Godot) estava desenhando a geometria secretamente. A renderização é 100% dependente da chamada indireta Vulkan.

### 3.4 Prova 5: Fallback de Diagnóstico Sob Demanda
- Ao acionar `pipeline.setup_multimesh_fallback()`, o MultiMesh e o material de cluster shader foram instanciados com sucesso (`instance_count = 367`).
- Ao acionar `pipeline.disable_multimesh_fallback()`, o fallback foi desativado e o caminho principal reassumiu o controle exclusivo.

---

## 4. LOG OFICIAL DE EXECUÇÃO DA SUÍTE DE TESTES

```text
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org
Vulkan 1.4.351 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 3050

=================================================================
   ARBORIA ENGINE — EXECUCAO DA SUITE DE TESTES: MISSAO 3/6     
=================================================================
[Hardware GPU] NVIDIA GeForce RTX 3050

--- INICIALIZANDO CARREGAMENTO NO CAMINHO PRINCIPAL (GPU PURO) ---
✅ Pipeline GPU Virtual Geometry pronto para execução! Total Clusters: 367 | VRAM: 863 KB

[PROVA 1] Verificacao de ausencia do MultiMesh no Caminho Principal
MultiMesh alocado no caminho principal? false
MultiMeshInstance3D alocado no caminho principal? false
STATUS PROVA 1: APROVADO

[PROVA 2] Renderizacao com Camera Proxima (5m) exclusivamente via GPU Indirect
VkDrawIndirectCommand da GPU (Camera 5m):
  - vertex_count:   384 (384 vertices por cluster)
  - instance_count: 170 (clusters visiveis compactados pela GPU)
  - first_vertex:   0
  - first_instance: 0
  - triangulos:     15607
  - clusters total: 367
  - tempo GPU:      6.14 us
Captura salva: 01_camera_proxima_gpu_main.png (Bytes: 314574)

[PROVA 3] Renderizacao com Camera Distante (35m) exclusivamente via GPU Indirect
VkDrawIndirectCommand da GPU (Camera 35m):
  - vertex_count:   384
  - instance_count: 53 (clusters visiveis compactados pela GPU)
  - first_vertex:   0
  - first_instance: 0
  - triangulos:     4209
  - clusters total: 367
  - tempo GPU:      7.17 us
Captura salva: 02_camera_distante_gpu_main.png (Bytes: 21594)
Selecao variou com distancia? true (170 -> 53 clusters)
STATUS PROVA 3: APROVADO

[PROVA 4] Teste Negativo: Desativar desenho indireto e verificar tela vazia
Captura salva: 03_teste_negativo_desativado.png
Pixels apagados ao desativar Indirect Draw: 230400
STATUS PROVA 4: APROVADO

[PROVA 5] Verificacao do Fallback de Diagnostico MultiMesh sob demanda
MultiMesh Fallback criado sob demanda com sucesso? true
Total de instâncias alocadas no fallback: 367
STATUS PROVA 5: APROVADO

=================================================================
                    RESUMO FINAL DOS TESTES                     
=================================================================
  - prova_1_multimesh_desacoplado: PASSOU
  - prova_3_comparacao_distancia: PASSOU
  - prova_4_teste_negativo: PASSOU
  - prova_5_fallback_sob_demanda: PASSOU
-----------------------------------------------------------------
RESULTADO GLOBAL: TODOS OS TESTES DA MISSAO 3/6 FORAM APROVADOS!
=================================================================
```

---

## 5. EVIDÊNCIAS DE CAPTURA EM DISCO

Salvas no diretório `AUDITORIA_FASE3_FINAL/evidencias/missao3/`:
- `01_camera_proxima_gpu_main.png` (314.574 bytes): Renderização em alta resolução da geometria via GPU Indirect a 5m (170 clusters, 15.607 triângulos).
- `02_camera_distante_gpu_main.png` (21.594 bytes): Renderização simplificada com seleção DAG LOD via GPU Indirect a 35m (53 clusters, 4.209 triângulos).
- `03_teste_negativo_desativado.png` (2.772 bytes): Viewport completamente vazio comprovando a ausência de qualquer renderizador fantasma.

---

## 6. LIMITAÇÕES ATUAIS DOCUMENTADAS

1. **Depth Buffer Local vs Scene Depth:** O renderizador indireto atualmente utiliza um Depth Attachment dedicado (`vp_depth_tex`) alocado via RenderingDevice para desenhar sobre o Viewport. Objetos padrão do Godot desenhados após o passe indireto não compartilham automaticamente este depth buffer sem injeção via Compositor ou SubPass.
2. **Cluster Shading PBR Completo:** O rasterizador indireto atual executa iluminação direcional básica no pixel shader com coloração de identificação de clusters (Nanite inspect mode). Shading de materiais PBR avançados de forward clustering será o foco de etapas posteriores de integração de materiais.

---

## 7. CONTRATO DE PARADA

A **Missão 3/6 foi concluída com êxito e evidências verificáveis**.  
O MultiMesh foi 100% removido do caminho principal de execução e isolado como fallback opcional.

Conforme determinação explícita da instrução:
**PARE APÓS ESTA MISSÃO.**
Parando agora e aguardando instruções para a Missão 4.
