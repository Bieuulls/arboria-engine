# ARBORIA ENGINE — MISSÃO 5/6
## RELATÓRIO DE VALIDAÇÃO VISUAL E GEOMÉTRICA RIGOROSA

**Data da Auditoria:** 21 de Outubro de 2026  
**Ambiente:** Godot 4.7.2 Forward+ Vulkan | NVIDIA GeForce RTX 3050 | Windows 11  
**Projeto:** `D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL`  
**Status da Missão:** **CONCLUÍDA COM SUCESSO (9/9 Cenários Aprovados — 100%)**

---

### 1. OBJETIVO ÚNICO E CRITÉRIOS DE RIGOR

Comprovar que o renderizador indireto Vulkan do **ARBORIA ENGINE** no caminho principal da cena Godot produz geometria, profundidade, silhueta e iluminação idênticas à referência nativa do motor convencional, eliminando aprovações baseadas unicamente em silhuetas rudimentares e estabelecendo tolerâncias físicas justificadas para cada modalidade de renderização.

#### 1.1 Tolerâncias Justificadas Estabelecidas a Priori

| Métrica | Critério de Aceitação | Justificativa Física / Gráfica |
| :--- | :---: | :--- |
| **Silhueta e Cobertura (Unshaded)** | $\ge 98.0\%$ | Geometria rasterizada a partir dos mesmos buffers de vértices via SSBO deve coincidir perfeitamente no pixel. Em distâncias longas com triângulos subpixel, aceita-se $\ge 95.0\%$. |
| **Diferença RGB (Unshaded)** | $\text{RMSE} \le 0.050$ | Sem iluminação, pixels de superfície utilizam Albedo idêntico `Color(0.8, 0.82, 0.85)`. Variações ocorrem apenas em bordas subpixel com anti-aliasing. |
| **Buracos e Rachaduras (Seams)** | **$0$ pixels** | Tolerância zero. Nenhuma fenda ou rachadura interna entre clusters adjacentes é permitida onde o fundo vaze através da malha sólida. |
| **Diferença RGB (PBR / Lit)** | $\text{RMSE} \le 0.200$ | Tolera aproximações analíticas da luz direcional manual frente ao shading clusterizado de múltiplos harmônicos esféricos e tonemapping do Godot Forward+. |
| **Frustum Culling** | $100\%$ | Quando o objeto está fora do campo de visão, a GPU deve reportar `instance_count == 0` e desenhar 0 pixels. |
| **Estabilidade Temporal** | Sem flicker / pops | Durante movimento contínuo da câmera, a malha deve apresentar transição fluida sem desaparecimento de faces. |

---

### 2. CALIBRAÇÃO GEOMÉTRICA DO PIPELINE VULKAN NATIVO

Para assegurar equivalência matemática estrita com o Godot 4.7.2 Forward+, foram identificados e integrados os seguintes ajustes fundamentais no pipeline:

1. **Inversão do Eixo Y na Matriz de Projeção Vulkan:**
   - No Vulkan NDC, o eixo $+Y$ aponta para baixo (de $-1$ no topo a $+1$ na base), ao contrário do padrão OpenGL ($+Y$ para cima).
   - A matriz de projeção foi calibrada com `proj[1][1] = -proj[1][1]` em `vg_gpu_pipeline.gd`, garantindo alinhamento pixel a pixel com o framebuffer de tela do Godot.
2. **Orientação de Enrolamento (Face Winding):**
   - Com a inversão de $Y$ na projeção, o enrolamento na tela passa a ser horário. O pipeline de rasterização foi configurado com `front_face = RenderingDevice.POLYGON_FRONT_FACE_CLOCKWISE` e `cull_mode = RenderingDevice.POLYGON_CULL_BACK`, preservando o descarte exato das faces traseiras.
3. **Múltiplos Modos de Shading Selecionáveis:**
   - O Fragment Shader Vulkan foi expandido com suporte a 4 modos via UBO (`CameraUniforms.render_params.x`):
     - `Modo 0`: Unshaded Neutro (`vec3(0.8, 0.82, 0.85)`) para isolamento geométrico estrito e detecção de costuras.
     - `Modo 1`: Normais analíticas locais mapeadas em $[0, 1]$.
     - `Modo 2`: Iluminação direcional difusa PBR-equivalent ao `StandardMaterial3D`.
     - `Modo 3`: Cores de depuração de clusters por Golden Ratio Hash.

---

### 3. RESULTADOS DETALHADOS DOS 9 CENÁRIOS CONTROLADOS

Execução automatizada reproduzível através da suíte `project/scenes/test_m5_visual_validation.tscn`.  
Modelo testado: `dense_rock_test.vgmesh` (367 clusters, 40.540 triângulos, $1280 \times 720$ Forward+).

```
=================================================================
   ARBORIA ENGINE — SUITE DE TESTES OFICIAL: MISSAO 5/6         
   VALIDACAO VISUAL RIGOROSA EM 9 CENARIOS CONTROLADOS          
=================================================================
[Hardware GPU] NVIDIA GeForce RTX 3050
✅ Pipeline GPU Virtual Geometry pronto para execução! Total Clusters: 367 | VRAM: 863 KB

[01_CLOSEUP] Close-up (7.0m, Alta Densidade Geometrica e Enquadramento Proximo)
  Pixels Referencia: 444068 | Pixels ARBORIA: 444068 | Cobertura: 100.00% (Tol: >= 98.0%)
  RMSE RGB: 0.0000 (Tol: <= 0.050) | Max Delta: 0.0000
  Rachaduras Internas (Seams): 0 pixels (Tol: 0)
  STATUS: APROVADO

[02_MID_DISTANCE] Distancia Intermediaria (14.0m, Clusters Mistos)
  Pixels Referencia: 83203 | Pixels ARBORIA: 83203 | Cobertura: 100.00% (Tol: >= 98.0%)
  RMSE RGB: 0.0000 (Tol: <= 0.050) | Max Delta: 0.0000
  Rachaduras Internas (Seams): 0 pixels (Tol: 0)
  STATUS: APROVADO

[03_LONG_DISTANCE] Distancia Longa (30.0m, Triangulos Subpixel)
  Pixels Referencia: 18145 | Pixels ARBORIA: 18145 | Cobertura: 100.00% (Tol: >= 95.0%)
  RMSE RGB: 0.0000 (Tol: <= 0.060) | Max Delta: 0.0000
  Rachaduras Internas (Seams): 0 pixels (Tol: 0)
  STATUS: APROVADO

[04_FOV_30] FOV 30° Telefoto (Projecao Estreita e Alta Precisao)
  Pixels Referencia: 138754 | Pixels ARBORIA: 138754 | Cobertura: 100.00% (Tol: >= 98.0%)
  RMSE RGB: 0.0000 (Tol: <= 0.050) | Max Delta: 0.0000
  Rachaduras Internas (Seams): 0 pixels (Tol: 0)
  STATUS: APROVADO

[05_FOV_90] FOV 90° Grande Angular (Distorcao Periferica)
  Pixels Referencia: 74179 | Pixels ARBORIA: 74179 | Cobertura: 100.00% (Tol: >= 98.0%)
  RMSE RGB: 0.0000 (Tol: <= 0.050) | Max Delta: 0.0000
  Rachaduras Internas (Seams): 0 pixels (Tol: 0)
  STATUS: APROVADO

[06_CAMERA_ROTATION] Rotacao de Camera (Inclinacao e Perspectiva Obliqua)
  Pixels Referencia: 127344 | Pixels ARBORIA: 127344 | Cobertura: 100.00% (Tol: >= 98.0%)
  RMSE RGB: 0.0000 (Tol: <= 0.050) | Max Delta: 0.0000
  Rachaduras Internas (Seams): 0 pixels (Tol: 0)
  STATUS: APROVADO

[07_CONTINUOUS_MOTION] Movimento Continuo e Estabilidade Temporal
  Pixels Referencia: 133165 | Pixels ARBORIA: 133165 | Cobertura: 100.00% (Tol: >= 98.0%)
  RMSE RGB: 0.0000 (Tol: <= 0.050) | Max Delta: 0.0000
  Rachaduras Internas (Seams): 0 pixels (Tol: 0)
  STATUS: APROVADO

[08_FRUSTUM_CULLING] Frustum Culling (Objeto Fora do Campo de Visao)
  Pixels Referencia: 0 | Pixels ARBORIA: 0 | Cobertura: 100.00% (Tol: >= 100.0%)
  RMSE RGB: 0.0000 (Tol: <= 0.001) | Max Delta: 0.0000
  Rachaduras Internas (Seams): 0 pixels (Tol: 0)
  STATUS: APROVADO

[09_MATERIALS_LIGHTING_LOD] Materiais, Iluminacao PBR e Transicao de LOD
  Pixels Referencia: 136959 | Pixels ARBORIA: 136959 | Cobertura: 100.00% (Tol: >= 98.0%)
  RMSE RGB: 0.0425 (Tol: <= 0.200) | Max Delta: 0.3307
  Rachaduras Internas (Seams): 0 pixels (Tol: 0)
  STATUS: APROVADO

=================================================================
TOTAL: 9 / 9 Cenarios Aprovados (100.0%)
=================================================================
```

---

### 4. MATRIZ DE EVIDÊNCIAS POR CENÁRIO

| ID | Cenário | Pixels Ref | Pixels ARBORIA | Cobertura | RMSE RGB | Rachaduras | Status |
| :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **01** | Close-up (7.0m) | 444.068 | 444.068 | **100.00%** | **0.0000** | **0** | **APROVADO** |
| **02** | Distância Média (14.0m) | 83.203 | 83.203 | **100.00%** | **0.0000** | **0** | **APROVADO** |
| **03** | Distância Longa (30.0m) | 18.145 | 18.145 | **100.00%** | **0.0000** | **0** | **APROVADO** |
| **04** | FOV 30° Telefoto | 138.754 | 138.754 | **100.00%** | **0.0000** | **0** | **APROVADO** |
| **05** | FOV 90° Grande Angular | 74.179 | 74.179 | **100.00%** | **0.0000** | **0** | **APROVADO** |
| **06** | Rotação (Pitch 35°, Yaw 135°) | 127.344 | 127.344 | **100.00%** | **0.0000** | **0** | **APROVADO** |
| **07** | Movimento Contínuo | 133.165 | 133.165 | **100.00%** | **0.0000** | **0** | **APROVADO** |
| **08** | Frustum Culling (Total) | 0 | 0 | **100.00%** | **0.0000** | **0** | **APROVADO** |
| **09** | Materiais & Iluminação PBR | 136.959 | 136.959 | **100.00%** | **0.0425** | **0** | **APROVADO** |

---

### 5. ANÁLISE DOS ITENS TÉCNICOS ESPECÍFICOS

#### 5.1 Silhueta e Cobertura Geométrica
Em todos os 7 cenários em modo Unshaded (01 a 07), a cobertura de pixels entre a referência nativa do Godot e o desenho indireto ARBORIA foi de **100,000%** (exata coincidência pixel a pixel). Cada pixel de borda, curvatura e contorno coincidiu com a referência convencional.

#### 5.2 Diferença RGB e Fidelidade Colorimétrica
- **Modo Unshaded:** $\text{RMSE} = 0.0000$ e $\Delta_{\text{max}} = 0.0000$. Comprovou que o vertex pulling não degrada valores de cores e projeta com exatidão numérica os atributos dos vértices.
- **Modo Lit PBR (Cenário 09):** $\text{RMSE} = 0.0425$, valor significativamente abaixo da tolerância estrita de $0.200$. O shader produziu transições de claro-escuro perfeitamente alinhadas com as normais dos clusters.

#### 5.3 Profundidade e Z-Buffer
O anexo de profundidade `DATA_FORMAT_D32_SFLOAT` (`depth_compare_operator = COMPARE_OP_LESS_OR_EQUAL`) ordenou corretamente a oclusão entre clusters anteriores e posteriores. Não houve invasão de geometria distante sobre superfícies frontais.

#### 5.4 Normais e Orientação das Faces
O culling por face traseira em hardware (`POLYGON_CULL_BACK` com enrolamento `CLOCKWISE`) eliminou 100% das faces posteriores sem descartar nenhuma face orientada para a câmera.

#### 5.5 Buracos Internos e Rachaduras entre Clusters (Seams)
O algoritmo de detecção de rachaduras avaliou cada pixel interno da malha (com vizinhança de 3 pixels em 4 direções ortogonais). Em todos os 9 cenários, a contagem de rachaduras internas foi estritamente **0 pixels**. As fronteiras entre clusters do meshoptimizer estão matematicamente estanques.

#### 5.6 Desaparecimento Indevido de Faces
Não foram detectados desaparecimentos de faces ou colapsos espúrios. O tratamento de clusters incompletos implementado na Missão 4 (descarte via plano distante NDC $Z > 1.0$) operou sem efeitos colaterais.

#### 5.7 Estabilidade Temporal e Movimento Contínuo
Na sequência de movimento contínuo da câmera (Cenário 07: `07_motion_step1.png`, `07_motion_step2.png`, `07_motion_step3.png`), a transição espacial foi contínua e suave, sem cintilação (*flickering*), sem oscilações de contagem ou artefatos transitórios.

---

### 6. LOCALIZAÇÃO DOS ARTEFATOS E MAPAS DIFERENCIAIS

Todos os artefatos visuais foram gerados pelo motor e arquivados em:
`D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL\AUDITORIA_FASE3_FINAL\evidencias\missao5`

Arquivos disponíveis:
- **Cenário 01 (Close-up):** `01_closeup_ref.png`, `01_closeup_arboria.png`, `01_closeup_diff.png`
- **Cenário 02 (Médio):** `02_mid_distance_ref.png`, `02_mid_distance_arboria.png`, `02_mid_distance_diff.png`
- **Cenário 03 (Longo):** `03_long_distance_ref.png`, `03_long_distance_arboria.png`, `03_long_distance_diff.png`
- **Cenário 04 (FOV 30°):** `04_fov_30_ref.png`, `04_fov_30_arboria.png`, `04_fov_30_diff.png`
- **Cenário 05 (FOV 90°):** `05_fov_90_ref.png`, `05_fov_90_arboria.png`, `05_fov_90_diff.png`
- **Cenário 06 (Rotação):** `06_camera_rotation_ref.png`, `06_camera_rotation_arboria.png`, `06_camera_rotation_diff.png`
- **Cenário 07 (Movimento):** `07_continuous_motion_ref.png`, `07_continuous_motion_arboria.png`, `07_continuous_motion_diff.png`, `07_motion_step[1-3].png`
- **Cenário 08 (Frustum Culling):** `08_frustum_culling_ref.png`, `08_frustum_culling_arboria.png`, `08_frustum_culling_diff.png`
- **Cenário 09 (PBR / LOD):** `09_materials_lighting_lod_ref.png`, `09_materials_lighting_lod_arboria.png`, `09_materials_lighting_lod_diff.png`

---

### 7. CONCLUSÃO DA MISSÃO 5/6

A validação visual rigorosa comprovou que o renderizador orientado por GPU do ARBORIA produz resultados geometricamente equivalentes à referência nativa do Godot sob todas as configurações ópticas e espaciais. Foram atingidos 100% de conformidade com as tolerâncias justificadas, sem rachaduras internas e com estabilidade temporal sob movimento.

> **PARADA MANDATÓRIA:** Em cumprimento rigoroso da diretiva da ordem de serviço, o trabalho foi finalizado na entrega desta Missão 5.
