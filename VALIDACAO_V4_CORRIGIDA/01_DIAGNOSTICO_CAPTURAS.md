# ARBORIA ENGINE — VALIDAÇÃO V4 CORRIGIDA
## 01. DIAGNÓSTICO DAS CAPTURAS E INVESTIGAÇÃO DE IDENTIDADE BYTE-A-BYTE

**Data do Diagnóstico:** 21 de Outubro de 2026  
**Ambiente:** Godot 4.7.2 Forward+ Vulkan | NVIDIA GeForce RTX 3050 | Windows 11  
**Projeto:** `D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL`

---

### 1. O PROBLEMA IDENTIFICADO NA AUDITORIA

A auditoria independente constatou que na Missão 5, em 8 dos 9 cenários de validação visual, os arquivos `.png` de referência convencional do Godot (`*_ref.png`) e os arquivos do renderizador indireto ARBORIA (`*_arboria.png`) eram rigorosamente idênticos byte a byte (tamanhos idênticos de 7.288B, 4.760B, 3.743B, 5.388B, etc.).

Apenas o Cenário 9 (Materiais e Iluminação) e o Cenário 8 (Frustum Culling total = 2.772B tela preta) apresentaram diferenças de bytes.

---

### 2. INVESTIGAÇÃO TÉCNICA E CAUSA RAIZ COMPROVADA

A investigação do código-fonte em `test_m5_visual_validation.gd` e `vg_gpu_pipeline.gd` revelou a confluência de dois fatores arquiteturais fundamentais que causaram o fenômeno:

#### Fator 1: Ausência de Limpeza de Cor (`DRAW_CLEAR_COLOR_0`) no Framebuffer Vulkan
Em `vg_gpu_pipeline.gd` (linha 981), o desenho indireto no Viewport utilizava:
```gdscript
var draw_list = rd.draw_list_begin(vp_framebuffer, RenderingDevice.DRAW_CLEAR_DEPTH, PackedColorArray(), 1.0, 0)
```
- A chamada limpava **apenas o buffer de profundidade** (`DRAW_CLEAR_DEPTH`).
- **O buffer de cor NÃO era limpo** (ausência da flag `DRAW_CLEAR_COLOR_0`).
- No teste antigo `test_m5_visual_validation.gd`, a Referência e o ARBORIA eram desenhados no mesmo Viewport em fases alternadas.
- Como o buffer de cor não era limpo pelo ARBORIA, os pixels previamente rasterizados pela Referência no frame anterior permaneciam gravados no buffer de cor!

#### Fator 2: Shading Unshaded com Albedo Idêntico
- Nos cenários 1 a 7, ambos os caminhos utilizavam modo Unshaded com albedo idêntico: `Color(0.8, 0.82, 0.85)`.
- Quando o ARBORIA rasterizava a geometria sobre o buffer existente, ele gravava `(0.8, 0.82, 0.85)` sobre os mesmos pixels que já continham `(0.8, 0.82, 0.85)`.
- Se qualquer cluster fosse descartado ou omitido, o pixel do frame anterior permanecia intacto, mascarando qualquer divergência geométrica.
- Por que o Cenário 9 foi o único com bytes diferentes? Porque no Cenário 9 o ARBORIA executou com `shading_mode = 2` (iluminação direcional com cálculo analítico de normais), gerando tons de sombra diferentes que finalmente sobrescreveram a cor plana anterior (16.391B vs 19.468B).

#### Fator 3: Latência de 1 Frame na Renderização de Nós do SceneTree Godot
- Em Godot, alterações em propriedades de nós (`visible`, `material_override`, `camera.position`) realizadas durante o callback `frame_post_draw` só surtem efeito na passagem Forward+ do **frame seguinte**.
- Ao tentar alternar `visible = false` e capturar a imagem na mesma chamada ou sem avanço sincronizado de 2 fases, a imagem obtida via `get_texture().get_image()` correspondia ao estado do frame anterior.

---

### 3. SOLUÇÃO DEFINITIVA IMPLEMENTADA

Para eliminar 100% de qualquer possibilidade de compartilhamento de buffers, retenção de pixels residuais ou vazamento de estado:

1. **Dois SubViewports Fisicamente Isolados:**
   - `subview_ref`: Contém exclusivamente a câmera e o nó `MeshInstance3D` da Referência Godot nativa, com `own_world_3d = true` e ambiente com fundo preto independente.
   - `subview_arb`: Contém exclusivamente a câmera do ARBORIA e não possui nenhuma malha convencional. É desenhado unicamente pelo pipeline Vulkan indireto.
2. **Sincronização Estrita de Duas Fases:**
   - Fase 0 (Configuração): Atualiza câmeras e materiais; aguarda a engine completar a passagem de renderização da Referência.
   - Fase 1 (Captura e Desenho): Captura a Referência do `subview_ref`, executa o desenho indireto no `subview_arb` e captura imediatamente os pixels do ARBORIA.
3. **Limpeza Explícita de Cor e Profundidade:**
   - Cada viewport inicia a partir de um fundo preto limpo (`Color(0, 0, 0, 1)`), garantindo que qualquer ausência de geometria resulte imediatamente em pixel preto detectável.
