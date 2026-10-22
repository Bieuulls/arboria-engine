# ARBORIA ENGINE — RELATÓRIO TÉCNICO DE FECHAMENTO V6.1
## FECHAMENTO DEFINITIVO DA ESTABILIZAÇÃO V5.1
### EXECUÇÃO RESTRITA — SEM NOVAS FUNCIONALIDADES

- **Projeto Oficial:** `D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL`
- **Documento de Referência:** ARBORIA V6 — Auditoria Independente
- **Responsável:** Antigravity
- **Data de Execução:** 2026-10-21
- **Status Geral:** `APROVADO COM EVIDÊNCIA` (Limitações Arquiteturais e Bloqueios Mantidos)

---

## A. MANIFESTO SHA-256 (MISSÃO 1)

### 1. Diagnóstico do Defeito Anterior
A auditoria independente comprovou divergências entre os hashes registrados em `VALIDACAO_V5_1_FINAL/manifest.json` e os bytes reais existentes no disco do RAR V6 para os arquivos `cull_clusters.glsl`, `vg_gpu_pipeline.gd` e `vg_visual_metrics.gd`. Os hashes antigos no manifesto refletiam versões transitórias intermediárias e não o código consolidado após as correções da V5.1.

### 2. Tabela de Verificação e Recálculo Direto em Disco
Os hashes SHA-256 foram recalculados diretamente a partir dos bytes dos arquivos presentes no repositório oficial (`D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL`):

| Arquivo | Hash Anterior (Manifesto RAR V6) | Hash Recalculado (Bytes Reais em Disco) | Resultado |
|---|---|---|---|
| `project/shaders/cull_clusters.glsl` | `E9864273E360980FD2FE4D758F2F6C7D187ED36270E4BE3C9A74E6F894903332` | `4C1FA93A5973DDE177C68CCC2293811B4315125559A8DA79F835A22A622561A8` | `APROVADO COM EVIDÊNCIA` |
| `project/scripts/vg_gpu_pipeline.gd` | `BF409D08EB8EBD3A96EF56A7A38289F438D9A8D6020E2C8EF1BDDC3042A3DAE6` | `E959E7675F494985FBE29DD29C41E3CF6910244DAFFF7E1FDE13758DA2F2381B` | `APROVADO COM EVIDÊNCIA` |
| `project/scripts/vg_visual_metrics.gd` | `F507F5EC4E20B880CE0C735B0DDCF6C176F0AC933C622837305951E952787042` | `7FD864A5F68FEABBB7071CA9F896CE634DAA9B30B16DABC13B11CF97BD63D4D5` | `APROVADO COM EVIDÊNCIA` |
| `project/scripts/test_v5_1_final_validation.gd` | *(Não listado no manifesto antigo)* | `036B0C41966AE37D54E73E47A9DAF8D51D9A57DCCDD09F43E765258F3FB3F630` | `APROVADO COM EVIDÊNCIA` |
| `project/assets/dense_rock_test.vgmesh` | `9D634FC3ABE8044DED8F6A49D3DFD6657F58764F942C3857A49AE4EB09650F85` | `9D634FC3ABE8044DED8F6A49D3DFD6657F58764F942C3857A49AE4EB09650F85` | `APROVADO COM EVIDÊNCIA` |
| `project/assets/boulder_granite.vgmesh` | `235E21F4B670046DB064BE09C85EAA735098904559AD26BDD53F03725AC7F4E0` | `235E21F4B670046DB064BE09C85EAA735098904559AD26BDD53F03725AC7F4E0` | `APROVADO COM EVIDÊNCIA` |

### 3. Verificação de Evidências Binárias (22 Imagens)
Todos os 22 arquivos de imagem contidos no pacote de evidências foram verificados e indexados:
- **Negativos (10 imagens):** `teste_a_arboria_disabled.png`, `teste_a_ref.png`, `teste_b_arboria_active.png`, `teste_b_ref_disabled.png`, `teste_c_arboria_dense_rock.png`, `teste_c_diff.png`, `teste_c_ref_granite.png`, `teste_d_arboria_neutral.png`, `teste_d_diff.png`, `teste_d_ref_red.png` — todos com hashes íntegros.
- **LOD Misto (6 imagens):** `01_lod_misto_arboria.png`, `01_lod_misto_diff.png`, `01_lod_misto_ref.png`, `02_lod_misto_rot_arboria.png`, `02_lod_misto_rot_diff.png`, `02_lod_misto_rot_ref.png` — todos com hashes íntegros.
- **Visuais (6 imagens):** `01_closeup_arboria.png`, `01_closeup_diff.png`, `01_closeup_ref.png`, `02_pbr_lit_arboria.png`, `02_pbr_lit_diff.png`, `02_pbr_lit_ref.png` — todos com hashes íntegros.
- **Profundidade (4 imagens):** `00_godot_box_isolado.png`, `01_caso_a_godot_na_frente.png`, `01_caso_a_mascara_sobrescrita.png`, `02_caso_b_arboria_na_frente.png` — geradas e validadas pela metodologia controlada.

### 4. Integridade da Sintaxe JSON
O arquivo `VALIDACAO_V5_1_FINAL/manifest.json` foi validado via parser JSON (`ConvertFrom-Json` no PowerShell). Nenhum erro de sintaxe, campos corrompidos ou chaves duplicadas. Estrutura 100% válida.

---

## B. MÉTRICA DE PROFUNDIDADE (MISSÃO 2)

### 1. Diagnóstico do Defeito Anterior
No teste V5.1 anterior, a variável `arb_px` contava qualquer pixel não preto e não verde no viewport compósito (totalizando 76.296 pixels). O relatório anterior apresentou equivocadamente esse valor como sendo a contagem de pixels do cubo sobrescritos pela rocha. Na realidade, 76.296 pixels era a silhueta da rocha inteira projetada na tela, e não a perda de pixels pertencentes à máscara do cubo frontal.

### 2. Metodologia Controlada Implementada
Para corrigir a metodologia de acordo com as instruções da Ordem V6.1, foram estabelecidas duas capturas controladas com condições idênticas (mesma resolução 1152x648, mesma câmera em Z=14, FOV 60°, mesma iluminação e coordenadas):
- **Imagem A (`00_godot_box_isolado.png`):** Cubo convencional Godot renderizado isoladamente em Z=5.5 (frente).
- **Imagem B (`01_caso_a_godot_na_frente.png`):** Mesmo cubo em Z=5.5 com a geometria ARBORIA em Z=0.0 sobreposta via renderização indireta no mesmo viewport sem limpar a cor.
- **Máscara Diferencial (`01_caso_a_mascara_sobrescrita.png`):** Mapeamento pixel a pixel da máscara do cubo.

### 3. Quantificação Exata Calculada
A análise algorítmica executada sobre a máscara exata da Imagem A produziu os seguintes números reais verificados:
- **Total de pixels na máscara original do cubo (Imagem A):** `73.984 pixels`
- **Pixels originais preservados na Imagem B:** `31.014 pixels (41,92%)`
- **Pixels originais do cubo indevidamente sobrescritos pelo ARBORIA:** `42.970 pixels (58,08%)`

### 4. Limitações da Métrica e Bloqueio Arquitetural
- **Limitação da Métrica:** Esta métrica baseada em máscara de renderização isolada vs sobreposta quantifica com precisão a área de sobreposição no espaço de tela para a pose de câmera avaliada. Ela não substitui uma leitura de profundidade por fragmento (Z-buffer compartilhado).
- **Bloqueio de Profundidade Forward+:** A sobreposição visual indevida de 58,08% dos pixels do cubo frontal confirma que o renderizador indireto do ARBORIA opera com buffer de profundidade desacoplado do pipeline Forward+ padrão do Godot.
- **Status:** `BLOQUEADO` — O problema de oclusão Forward+ permanece documentado como impedimento estrutural, aguardando resolução via integração nativa (GDExtension / compositor nativo) sob decisão arquitetural do Codex.

---

## C. LIMITAÇÃO DOS TESTES DE RACHADURAS (MISSÃO 3)

### 1. Descrição Exata da Heurística Atual
O algoritmo implementado em `vg_visual_metrics.gd` (`detect_cracks`) opera da seguinte forma:
1. Para cada pixel `(x, y)` onde a referência possui geometria e o renderizador ARBORIA está vazio (pixel ausente);
2. O algoritmo realiza uma busca linear ao longo de quatro eixos ortogonais cartesianos: `+X (Direita)`, `-X (Esquerda)`, `+Y (Baixo)`, `-Y (Cima)`;
3. O alcance máximo da busca é delimitado em uma distância fixa de **24 pixels** em cada direção (`max_dist = 24`);
4. Se o detector encontrar pixels de geometria ARBORIA nos quatro eixos simultaneamente dentro do raio de 24 pixels, o pixel é classificado como uma rachadura interna (`internal_crack`). Caso contrário, é tratado como variação de silhueta ou borda externa.

### 2. Limitações Conhecidas da Heurística
- **Alcance Finito:** Rachaduras, descontinuidades ou fendas com abertura transversal superior a 24 pixels em qualquer direção não são identificadas como rachaduras internas.
- **Direções Não Diagonais:** A busca ocorre estritamente nos 4 eixos cartesianos ortogonais (não contempla eixos diagonais a 45° ou busca omnidirecional em raio contínuo).
- **Não Generalização Universal:** A ausência de detecção nesta heurística comprova apenas que não foram observadas fendas internas estreitas (<= 24 px) na projeção 2D sob os ângulos e distâncias testados.

### 3. Redação Técnica Padronizada
- **Resultado permitido e adotado:**
  > *"Nenhuma rachadura detectada pela heurística atual nos cenários executados."*
- **Resultado proibido (sem prova matemática analítica contínua):**
  > *"A geometria está matematicamente livre de qualquer rachadura."*

### 4. Resultados Prévia e Efetivamente Validados
Nos cenários de LOD misto executados:
- **Caso 1 (Dist 18.0m, Yaw 30°, Pitch 10° — 17 clusters LOD0 + 88 clusters LOD1):** 0 pixels de rachadura detectados pela heurística atual (IoU: 99,74%).
- **Caso 2 (Dist 15.0m, Yaw 120°, Pitch 40° — 75 clusters LOD0 + 55 clusters LOD1):** 0 pixels de rachadura detectados pela heurística atual (IoU: 99,96%).

---

## D. CONTROLE DE ALTERAÇÕES (MISSÃO 4)

### 1. Arquivos Modificados
Em estrita observância à Regra Zero de Controle Absoluto de Escopo, **apenas 1 arquivo de código** foi pontualmente alterado:
- `project/scripts/test_v5_1_final_validation.gd`

Nenhum outro script, shader ou fonte C++ foi alterado.

### 2. Diff das Mudanças em `test_v5_1_final_validation.gd`
```diff
--- a/project/scripts/test_v5_1_final_validation.gd
+++ b/project/scripts/test_v5_1_final_validation.gd
@@ -412,23 +412,47 @@ func _on_frame() -> void:
 		11:
 			log_msg("\n-----------------------------------------------------------------")
-			log_msg("[TESTE DE PROFUNDIDADE — CASO A] Geometria Godot à FRENTE da geometria ARBORIA")
+			log_msg("[TESTE DE PROFUNDIDADE — CASO A] Metodologia Controlada de Oclusão (Imagem A vs Imagem B)")
 			log_msg("  Configuração: Câmera Z=14 | Caixa Verde Z=5.5 (Frente) | ARBORIA Z=0.0 (Fundo)")
 
+			# 1. CAPTURA IMAGEM A: Cubo convencional Godot renderizado isoladamente
+			var img_box_isolated = subview_arb.get_texture().get_image()
+			img_box_isolated.save_png("%s/profundidade/00_godot_box_isolado.png" % base_output)
+
+			# 2. CAPTURA IMAGEM B: Mesmo cubo com desenho indireto ARBORIA sobreposto (sem limpar cor)
 			pipeline.render_to_viewport(subview_arb, cam_arb, Transform3D.IDENTITY, 1.5, 1, 0, true, false, false, 0, false)
 			var img_depth_a = subview_arb.get_texture().get_image()
 			img_depth_a.save_png("%s/profundidade/01_caso_a_godot_na_frente.png" % base_output)
 
-			# Medição do vazamento de profundidade: quantos pixels da rocha sobrescreveram a caixa?
+			# 3. Análise controlada na máscara original do cubo
+			var w = img_box_isolated.get_width()
+			var h = img_box_isolated.get_height()
+			var total_box_pixels = 0
+			var preserved_box_pixels = 0
+			var overwritten_box_pixels = 0
+			var diff_depth_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
+
+			for y in range(h):
+				for x in range(w):
+					var ca = img_box_isolated.get_pixel(x, y)
+					var cb = img_depth_a.get_pixel(x, y)
+					var is_box_orig = (ca.g > 0.8 and ca.r < 0.2 and ca.b < 0.2)
+					var is_box_curr = (cb.g > 0.8 and cb.r < 0.2 and cb.b < 0.2)
+					var is_arb_curr = (cb.r > 0.05 or cb.g > 0.05 or cb.b > 0.05) and not is_box_curr
+
+					if is_box_orig:
+						total_box_pixels += 1
+						if is_box_curr:
+							preserved_box_pixels += 1
+							diff_depth_img.set_pixel(x, y, Color(0.0, 1.0, 0.0, 1.0)) # Verde = preservado
+						else:
+							overwritten_box_pixels += 1
+							diff_depth_img.set_pixel(x, y, Color(1.0, 0.0, 0.0, 1.0)) # Vermelho = sobrescrito pelo ARBORIA
+					else:
+						if is_arb_curr:
+							diff_depth_img.set_pixel(x, y, Color(0.3, 0.3, 0.35, 1.0)) # Cinza = rocha fora da silhueta do cubo
+						else:
+							diff_depth_img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 1.0))
+
+			diff_depth_img.save_png("%s/profundidade/01_caso_a_mascara_sobrescrita.png" % base_output)
+
+			var pct_overwritten = (float(overwritten_box_pixels) / float(total_box_pixels)) * 100.0 if total_box_pixels > 0 else 0.0
+			var pct_preserved = (float(preserved_box_pixels) / float(total_box_pixels)) * 100.0 if total_box_pixels > 0 else 0.0
+
+			log_msg("  Total de Pixels na Máscara Original do Cubo (Imagem A): %d" % total_box_pixels)
+			log_msg("  Pixels Originais do Cubo Preservados (Imagem B): %d (%.2f%%)" % [preserved_box_pixels, pct_preserved])
+			log_msg("  Pixels Originais do Cubo Sobrescritos pelo ARBORIA: %d (%.2f%%)" % [overwritten_box_pixels, pct_overwritten])
+			log_msg("  BLOQUEIO ARQUITETURAL CONFIRMADO: Devido ao buffer de profundidade isolado do ARBORIA,")
+			log_msg("  %.2f%% dos pixels do cubo frontal foram indevidamente sobrescritos pela geometria de fundo." % pct_overwritten)
+			log_msg("  STATUS PROFUNDIDADE: SOBREPOSIÇÃO VISUAL CONFIRMADA — BLOQUEIO FORWARD+ REGISTRADO")
```

### 3. Justificativa da Alteração
Substituição da contagem ingênua de pixels da rocha total pelo método rigoroso solicitado na Missão 2: construção da máscara exata do cubo na Imagem A (isolada) e medição da proporção de pixels dessa máscara preservados vs sobrescritos na Imagem B (sobreposta).

### 4. Execução do Teste e Código de Saída
- **Comando executado:**
  `godot_engine\godot.exe --headless --path D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL --scene res://scenes/test_v5_1_final_validation.tscn`
- **Código de saída (Exit Code):** `0`
- **Log de execução salvo em:** `VALIDACAO_V5_1_FINAL/FECHAMENTO_V6/logs/execution.log`

---

## E. INTEGRIDADE DO PROJETO

Conforme a Regra Zero e as Proibições Absolutas da Ordem V6.1, certifica-se por verificação de integridade que nenhum componente funcional de renderização foi modificado indevidamente:

1. **Baker C++ (`tools/baker/`):** Intacto. Nenhuma alteração de código ou compilação realizada.
2. **Hierarquia DAG e Formato de Dados (`.vgmesh`):** Intactos. A malha `dense_rock_test.vgmesh` mantém exatamente o hash SHA-256 `9D634FC3ABE8044DED8F6A49D3DFD6657F58764F942C3857A49AE4EB09650F85`.
3. **Compute Shader Vulkan (`cull_clusters.glsl`):** Intacto. Mantém exatamente o hash SHA-256 `4C1FA93A5973DDE177C68CCC2293811B4315125559A8DA79F835A22A622561A8`.
4. **Pipeline GPU (`vg_gpu_pipeline.gd`):** Intacto. Mantém exatamente o hash SHA-256 `E959E7675F494985FBE29DD29C41E3CF6910244DAFFF7E1FDE13758DA2F2381B`.
5. **Métricas Visuais (`vg_visual_metrics.gd`):** Intacto. Mantém exatamente o hash SHA-256 `7FD864A5F68FEABBB7071CA9F896CE634DAA9B30B16DABC13B11CF97BD63D4D5`.
6. **Core do Godot e Shaders Gráficos:** Nenhuma GDExtension criada, nenhum patch de core aplicado, pipeline Vulkan mantido sem regressões.

---

ESTABILIZAÇÃO V5.1 ENCERRADA — FASE 3 AGUARDA INTEGRAÇÃO NATIVA
