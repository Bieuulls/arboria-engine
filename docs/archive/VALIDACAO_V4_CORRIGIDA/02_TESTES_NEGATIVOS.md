# ARBORIA ENGINE — VALIDAÇÃO V4 CORRIGIDA
## 02. TESTES NEGATIVOS OBRIGATÓRIOS DO RENDERIZADOR

**Data de Execução:** 21 de Outubro de 2026  
**Ambiente:** Godot 4.7.2 Forward+ Vulkan | NVIDIA GeForce RTX 3050 | Windows 11  
**Projeto:** `D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL`  
**Script do Teste:** `project/scripts/test_v4_negative_tests.gd`  
**Cena:** `project/scenes/test_v4_negative_tests.tscn`

---

### 1. OBJETIVO DOS TESTES NEGATIVOS

Comprovar, de maneira irrefutável e matematicamente auditável, que:
1. O caminho convencional do Godot e o pipeline de desenho indireto Vulkan do ARBORIA operam como geradores de imagem independentes.
2. A desativação ou alteração de um dos pipelines não afeta o outro.
3. Não há vazamento de pixels, compartilhamento oculto de buffers de cor nem reutilização indevida de dados entre os caminhos.

Qualquer falha nestes 4 testes resultaria na reprovação sumária da validação.

---

### 2. COMANDO DE EXECUÇÃO E REPRODUÇÃO

```bash
d:\ARBORIA_ENGINE\bin\godot_console.exe --rendering-driver vulkan --headless --path D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL\project scenes/test_v4_negative_tests.tscn
```

---

### 3. METODOLOGIA E ISOLAMENTO DE VIEWPORTS

Para garantir a independência física absoluta dos canais:
- O teste instancia dois nós `SubViewport` de 1024x1024:
  - `subview_ref`: Possui `own_world_3d = true`, câmera própria e renderiza exclusivamente a malha convencional (`MeshInstance3D`).
  - `subview_arb`: Possui câmera própria, sem nós de malha convencionais. É rasterizado exclusivamente via chamadas Vulkan indiretas (`rd.draw_list_draw_indirect`) em `_on_frame_post_draw`.
- As capturas de pixels são realizadas via `get_texture().get_image()` com avanço de frames sincronizado para contornar a latência de 1 frame do Forward+ do Godot.

---

### 4. RESULTADOS E MÉTRICAS POR TESTE

#### TESTE A: Desativação do Desenho Indireto ARBORIA
- **Condição:** Geometria convencional Godot ativa (`visible = true`). Chamada `render_to_viewport()` do ARBORIA suspensa (`visible = false` / suprimida).
- **Critério de Aprovação:** A malha convencional deve renderizar normalmente na Referência (> 1.000 px não-pretos); o viewport ARBORIA deve permanecer totalmente preto (0 px não-pretos).
- **Métricas Obtidas:**
  - `ref_non_black_px`: **107.996**
  - `arb_non_black_px`: **0**
- **Status:** **APROVADO (PASS)**
- **Arquivos de Evidência:**
  - Referência: `evidencias/negativos/teste_a_ref.png` (5.049 bytes)
  - ARBORIA: `evidencias/negativos/teste_a_arboria_disabled.png` (2.772 bytes — tela 100% preta)

#### TESTE B: Desativação da Geometria de Referência Convencional
- **Condição:** Geometria convencional Godot desativada (`mesh_node.visible = false`). Pipeline de desenho indireto ARBORIA ativo.
- **Critério de Aprovação:** O viewport da Referência deve permanecer totalmente preto (0 px não-pretos); o ARBORIA deve renderizar normalmente (> 1.000 px).
- **Métricas Obtidas:**
  - `ref_non_black_px`: **0**
  - `arb_non_black_px`: **107.996**
- **Status:** **APROVADO (PASS)**
- **Arquivos de Evidência:**
  - Referência: `evidencias/negativos/teste_b_ref_disabled.png` (2.772 bytes — tela 100% preta)
  - ARBORIA: `evidencias/negativos/teste_b_arboria_active.png` (5.049 bytes)

#### TESTE C: Alteração de Cor de Diagnóstico em Apenas Um dos Caminhos
- **Condição:** A Referência Godot recebe material vermelho vivo (`Color(1.0, 0.0, 0.0)`). O ARBORIA mantém sua cor neutra (`Color(0.8, 0.82, 0.85)`).
- **Critério de Aprovação:** A Referência deve conter pixels vermelhos (> 1.000 px) e o ARBORIA não deve conter nenhum pixel vermelho (0 px).
- **Métricas Obtidas:**
  - `ref_red_px`: **107.996**
  - `arb_red_px`: **0**
  - `arb_neutral_px`: **107.996**
- **Status:** **APROVADO (PASS)**
- **Arquivos de Evidência:**
  - Referência: `evidencias/negativos/teste_c_ref_red.png` (5.064 bytes — malha vermelha pura)
  - ARBORIA: `evidencias/negativos/teste_c_arboria_neutral.png` (5.049 bytes — malha cinza neutra)

#### TESTE D: Modelos Geometricamente Diferentes
- **Condição:** Referência carrega `granite_rock.vgmesh` (geometria menor, 14.805 px de projeção). ARBORIA carrega `dense_rock_lod0.vgmesh` (geometria densa e volumosa, 107.996 px de projeção).
- **Critério de Aprovação:** O teste deve detectar a divergência geométrica entre as silhuetas, com sobreposição (IoU) inferior a 95%.
- **Métricas Obtidas:**
  - `ref_px`: **14.805**
  - `arb_px`: **107.996**
  - `overlap_iou`: **13,71%** (divergência maciça detectada com sucesso)
- **Status:** **APROVADO (PASS)**
- **Arquivos de Evidência:**
  - Referência: `evidencias/negativos/teste_d_ref_granite.png` (3.594 bytes)
  - ARBORIA: `evidencias/negativos/teste_d_arboria_dense_rock.png` (5.049 bytes)

---

### 5. TABELA RESUMO DOS TESTES NEGATIVOS

| Teste | Hipótese Testada | Ref Px | Arb Px | Métrica Chave | Veredito |
|---|---|---|---|---|---|
| **A** | Desativação ARBORIA | 107.996 | 0 | Arb = 0 px | **APROVADO** |
| **B** | Desativação Godot | 0 | 107.996 | Ref = 0 px | **APROVADO** |
| **C** | Mutação de Cor Ref (Vermelho) | 107.996 | 0 | Arb Red = 0 px | **APROVADO** |
| **D** | Modelos Diferentes (Granite vs Dense) | 14.805 | 107.996 | IoU = 13,71% | **APROVADO** |

---

### 6. CONCLUSÃO TÉCNICA

Todos os 4 testes negativos foram executados com rigor absoluto e obtiveram aprovação de 100%. Comprovou-se definitivamente que os renderizadores são física e logicamente desacoplados, não compartilham estados espúrios e reagem de forma autônoma e correta a alterações de malha, visibilidade e materiais.
