# ARBORIA ENGINE — VALIDAÇÃO V4 CORRIGIDA
## 04. INVESTIGAÇÃO DE PROFUNDIDADE E INTERAÇÃO COM O FORWARD+

**Data de Execução:** 21 de Outubro de 2026  
**Ambiente:** Godot 4.7.2 Forward+ Vulkan | NVIDIA GeForce RTX 3050 | Windows 11  
**Projeto:** `D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL`  
**Script do Teste:** `project/scripts/test_v4_depth_investigation.gd`  
**Cena:** `project/scenes/test_v4_depth_investigation.tscn`

---

### 1. OBJETIVO DA INVESTIGAÇÃO

Verificar conclusivamente se a geometria rasterizada pelo pipeline indireto do ARBORIA:
1. Participa de um teste de profundidade (*depth test*) bidirecional com a geometria convencional do Godot; OU
2. Executa apenas uma composição visual / sobreposição (*compositing overlay*) no final do frame.

**Diretriz do Usuário:**  
*“Se existir uma limitação real da API, documente-a. Não tente esconder a limitação utilizando ordenação artificial, sobreposição de texturas ou outros efeitos que apenas simulem profundidade correta. Não modifique o núcleo do Godot nesta missão.”*

---

### 2. COMANDO DE EXECUÇÃO E REPRODUÇÃO

```bash
d:\ARBORIA_ENGINE\bin\godot_console.exe --rendering-driver vulkan --headless --path D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL\project scenes/test_v4_depth_investigation.tscn
```

---

### 3. METODOLOGIA DO TESTE DE OCLUSÃO

Construiu-se uma cena mínima contendo:
- **Objeto Godot Convencional:** Um cubo verde (`MeshInstance3D`, dimensões 2.5m x 2.5m x 2.5m, material Unshaded verde puro `Color(0.0, 1.0, 0.0)`).
- **Objeto ARBORIA Indireto:** Malha `dense_rock_lod0.vgmesh` rasterizada indiretamente na GPU com material neutro cinza (`Color(0.8, 0.82, 0.85)`).
- **Câmera Comum:** Posicionada em `(0, 0, 10)` apontada para a origem.
- **Sobreposição Espacial:** Os objetos foram posicionados com interseção parcial no plano de visão da câmera.

---

### 4. DADOS QUANTITATIVOS E RESULTADOS OBTIDOS

#### Linha de Base de Controle: Cubo Godot Isolado
- O cubo foi renderizado sozinho na posição `Vector3(-0.6, 0.0, 2.0)`.
- Total de pixels verdes projetados: **73.984 pixels**.
- Arquivo de Evidência: `evidencias/profundidade/00_godot_box_isolado.png`.

---

#### CASO A: Cubo Godot À FRENTE da Geometria ARBORIA
- **Posição do Cubo Godot:** `Z = +2.0m` (mais próximo da câmera).
- **Posição da Rocha ARBORIA:** `Z = -0.5m` (mais distante da câmera, atrás do cubo).
- **Comportamento Esperado em Profundidade Real:** O cubo verde está mais próximo da câmera; portanto, nenhum de seus pixels deveria ser encoberto pela rocha que está atrás. Todos os **73.984 pixels** deveriam permanecer visíveis.
- **Resultado Real Medido:**
  - Pixels verdes visíveis: **31.014 pixels**
  - Pixels da rocha ARBORIA visíveis: **74.150 pixels**
  - **Pixels do Cubo Godot sobrescritos:** **42.970 pixels**
  - **Percentual de perda do objeto frontal:** **58,08%** do cubo verde frontal foi completamente apagado e sobrescrito pela geometria ARBORIA que estava atrás dele!
- **Arquivo de Evidência:** `evidencias/profundidade/01_caso_a_godot_na_frente.png`.

---

#### CASO B: Geometria ARBORIA À FRENTE do Cubo Godot
- **Posição da Rocha ARBORIA:** `Z = +2.0m` (mais próxima da câmera).
- **Posição do Cubo Godot:** `Z = -2.0m` (mais distante da câmera, atrás da rocha).
- **Resultado Real Medido:**
  - Pixels verdes visíveis: **0 pixels** (totalmente ocluído).
  - Pixels da rocha ARBORIA visíveis: **76.296 pixels**.
- **Arquivo de Evidência:** `evidencias/profundidade/02_caso_b_arboria_na_frente.png`.

---

### 5. CAUSA RAIZ ARQUITETURAL: LIMITAÇÃO DA API RENDERINGDEVICE EM GDSCIPT

A inspeção do pipeline em `vg_gpu_pipeline.gd` (linhas 965 a 995) comprova a causa exata do comportamento:

1. **Momento da Execução (`frame_post_draw`):**
   - O sinal `RenderingServer.frame_post_draw` é disparado após o Godot concluir todas as passagens da fila 3D Forward+ (Shadow, Depth Prepass, Opaque Pass, Transparent Pass, Tonemapping).
   - O Viewport já terminou de escrever a imagem final no buffer de cor.

2. **Buffer de Profundidade Próprio e Isolado:**
   - Para rasterizar a geometria indireta, o ARBORIA cria um buffer de profundidade privado na GPU:
     ```gdscript
     vp_depth_tex = rd.texture_create(tf, RenderingDevice.TextureView.new(), []) # D32_SFLOAT
     ```
   - Esse `vp_depth_tex` é anexado ao framebuffer do ARBORIA (`vp_framebuffer`) junto com a textura de cor do Viewport do Godot.
   - O ARBORIA executa o Depth Testing **exclusivamente contra o seu próprio `vp_depth_tex`**.

3. **Inacessibilidade do Buffer de Profundidade do Forward+ via GDScript:**
   - A API pública de GDScript do Godot 4.7.2 (`RenderingServer` / `RenderingDevice`) permite recuperar o RID da textura de cor do viewport (`viewport.get_texture().get_rid()`), mas **não permite vincular o Depth Attachment interno do renderizador Forward+ como render target de uma lista de desenho externa**.
   - Como resultado, quando o ARBORIA desenha em `frame_post_draw`, ele rasteriza sobre o buffer de cor já finalizado do Godot sem conhecimento dos valores de profundidade previamente gravados pelos objetos convencionais.

---

### 6. CLASSIFICAÇÃO TÉCNICA DEFINITIVA

| Pergunta Técnica | Resposta Conclusiva |
|---|---|
| O sistema realiza teste de profundidade real mútuo com o Forward+? | **NÃO.** |
| O sistema realiza composição visual sobreposta (*post-pass overlay*)? | **SIM.** |
| A geometria ARBORIA testa profundidade entre seus próprios clusters? | **SIM** (via `vp_depth_tex` privado D32_SFLOAT). |
| A geometria ARBORIA respeita a oclusão de objetos convencionais Godot à sua frente? | **NÃO** (sobrescreve 58% a 100% dos pixels convencionais à frente). |

---

### 7. CONCLUSÃO TÉCNICA E LIMITAÇÃO DOCUMENTADA

O ARBORIA Engine na arquitetura atual de GDScript opera como um **renderizador em sobreposição pós-passe**. 

Para que ocorra teste de profundidade nativo bidirecional com a cena 3D do Godot sem modificar o núcleo da engine, será necessário implementar no futuro um plugin C++ via **GDExtension** utilizando a classe **`CompositorEffect`** com flag de inserção nos estágios intermediários do render pipeline (`COMPOSITOR_STAGE_OPAQUE` ou `COMPOSITOR_STAGE_POST_OPAQUE`), compartilhando o buffer de profundidade nativo do renderizador.
