# ARBORIA ENGINE — ORDEM TÉCNICA V5.1
## RELATÓRIO TÉCNICO OFICIAL DE ESTABILIZAÇÃO DOS TESTES ANTES DA INTEGRAÇÃO NATIVA

**Projeto Oficial:** `D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL`  
**Data de Execução:** 21 de Outubro de 2026  
**Ambiente de Execução:** Windows 10 Pro 64-bit | Godot 4.7.2.stable Vulkan Forward+ | NVIDIA GeForce RTX 3050 Laptop GPU  
**Diretório de Entrega:** `D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL\VALIDACAO_V5_1_FINAL`

---

## 1. INTRODUÇÃO E ESCOPO DA MISSÃO

A missão técnica V5.1 foi instaurada com o objetivo estrito de **eliminar os defeitos comprovados do sistema de validação**, **corrigir matematicamente as métricas de IoU**, **investigar a integridade do corte hierárquico em LODs mistos** e **estabelecer a independência verificável dos testes** antes do início da integração nativa ao Godot Forward+.

Seguindo a regra principal da ordem técnica:
- Nenhum código foi modificado sem prévia reprodução do defeito e isolamento de sua causa raiz.
- Toda alteração de código foi mínima, cirúrgica e acompanhada de testes unitários e de regressão.
- As asserções de teste provocam encerramento imediato com código de erro não-zero em caso de discrepância.

---

## 2. ETAPA 1 — IDENTIFICAÇÃO DA FONTE VERDADEIRA DOS RESULTADOS

### 2.1 Identidade e Hash do Arquivo `.vgmesh` Utilizado
Foi realizado o inventário físico dos arquivos de geometria virtual utilizados nos testes. O modelo oficial do cenário de validação primário é:
- **Arquivo:** `project/assets/dense_rock_test.vgmesh`
- **Hash SHA-256:** `9D634FC3ABE8044DED8F6A49D3DFD6657F58764F942C3857A49AE4EB09650F85`
- **Tamanho:** 840.674 bytes
- **Metadados Reais Lidos Diretamente do Cabeçalho Binário:**
  - `total_clusters`: 367 clusters
  - `total_lods`: 9 níveis hierárquicos
  - `total_groups`: 27 grupos DAG
  - `lod 0`: 172 clusters | 15.800 triângulos (Erro Máximo: 0.0)
  - `lod 1`: 97 clusters | 7.888 triângulos (Erro Máximo: 0.038348)
  - `lod 2`: 49 clusters | 3.940 triângulos (Erro Máximo: 0.085911)
  - `lod 3`: 24 clusters | 1.968 triângulos (Erro Máximo: 0.188587)
  - `lod 4`: 13 clusters | 982 triângulos (Erro Máximo: 0.425123)
  - `lod 5`: 6 clusters | 490 triângulos (Erro Máximo: 0.664999)
  - `lod 6`: 3 clusters | 244 triângulos (Erro Máximo: 1.199213)
  - `lod 7`: 2 clusters | 122 triângulos (Erro Máximo: 1.948194)
  - `lod 8`: 1 cluster | 60 triângulos (Erro Máximo: 2.791558)
  - Distribuição Total: `{ 0: 172, 1: 97, 2: 49, 3: 24, 4: 13, 5: 6, 6: 3, 7: 2, 8: 1 }` = 367 clusters.

*Nota de Auditoria:* Relatórios anteriores citavam erroneamente "283 clusters totais e 4 níveis". A leitura direta do binário comprovou que a malha possui 367 clusters em 9 níveis de LOD.

### 2.2 Rastreamento das Imagens Antigas e Causa do IoU de 79.9%
A análise espacial e estatística da imagem legada `02_mid_dag_unshaded` (que apresentava 79.9% de IoU) revelou:
1. **Deslocamento de Câmera (Centroides Divergentes):** O centroide X da Referência estava em 634.60 px, enquanto o centroide X do ARBORIA estava em 656.49 px (uma defasagem espacial de mais de 20 pixels horizontais).
2. **Latência de 1 frame do Godot SceneTree:** Na implementação legada `test_visual_validation.gd` (com `MultiMeshInstance3D`), as alternâncias de nós e transformações de câmera demoravam 1 frame para serem aplicadas pelo Godot, fazendo com que a Referência e o ARBORIA fossem capturados com 1 frame de dessincronização de ângulo, gerando corte lateral espúrio e a métrica de 79.9%.

---

## 3. ETAPA 2 — CORREÇÃO DOS DEFEITOS DE CAPTURA

### 3.1 Defeito Comprovado no Buffer de Framebuffer
Em `vg_gpu_pipeline.gd`, a função `render_to_viewport()` iniciava o render pass fixo com:
```gdscript
var draw_list = rd.draw_list_begin(vp_framebuffer, RenderingDevice.DRAW_CLEAR_DEPTH, PackedColorArray(), 1.0, 0)
```
E se `enable_indirect_draw == false`, a função retornava imediatamente sem limpar o framebuffer.
- **Consequência:** Na renderização isolada, ao desativar o ARBORIA, os pixels desenhados no frame anterior permaneciam no framebuffer (retenção de geometria residual).

### 3.2 Correção Mínima Implementada
Adicionado suporte ao parâmetro `p_clear_color: bool = false, p_clear_color_val: Color = Color(0, 0, 0, 1)`:
- Quando `p_clear_color == false` (comportamento padrão na cena com objetos Godot): limpa exclusivamente o buffer de profundidade (`DRAW_CLEAR_DEPTH`), garantindo que **nenhum objeto convencional desenhado pelo Forward+ seja apagado**.
- Quando `p_clear_color == true` (modo isolado de teste): limpa cor e profundidade (`DRAW_CLEAR_COLOR_0 | DRAW_CLEAR_DEPTH`).
- Se `enable_indirect_draw == false` e `p_clear_color == true`: executa a limpeza explícita do framebuffer para garantir que a imagem isolada fique com zero pixels (fundo preto puro).
- Sincronização: Eliminadas chamadas ilegais a `rd.submit()` e `rd.sync()` no contexto global do `RenderingDevice`, utilizando as barreiras e conclusões de submissão nativas do loop de renderização do Godot.

### 3.3 Comprovação da Prova Negativa
Com o desenho indireto desligado (`enable_indirect_draw = false`), a captura isolada registrou rigorosamente **0 pixels**, comprovando que não há vazamento nem retenção de geometria de frames anteriores.

---

## 4. ETAPA 3 — CORREÇÃO MATEMÁTICA DA VALIDAÇÃO VISUAL (IoU VERDADEIRO)

### 4.1 Substituição da Proporção Falsa por IoU Verdadeiro
O teste anterior utilizava a fórmula inválida `min(ref, arb) / max(ref, arb)`.
Foi criada a biblioteca formal `VGVisualMetrics` (`project/scripts/vg_visual_metrics.gd`), que implementa a definição de IoU:
$$\text{IoU} = \frac{|\text{Máscara}_{\text{Ref}} \cap \text{Máscara}_{\text{Arb}}|}{|\text{Máscara}_{\text{Ref}} \cup \text{Máscara}_{\text{Arb}}|}$$

### 4.2 Testes Unitários com Resultados Conhecidos a Priori (`test_unit_iou_metrics.gd`)
Foram executados 5 testes unitários puros com asserções estritas (`quit(1)` em qualquer falha):
1. **Máscaras Iguais:** 1600 px sobre 1600 px $\rightarrow$ IoU = **1.000000** (Esperado: 1.0) $\rightarrow$ **APROVADO**.
2. **Máscaras Sem Interseção:** Imagens disjuntas $\rightarrow$ IoU = **0.000000** (Esperado: 0.0). *A proporção falsa min/max informaria 100% erroneamente, mascarando o defeito*. $\rightarrow$ **APROVADO**.
3. **Máscaras Parcialmente Sobrepostas:** Retângulos com 50 px comuns e 150 px união $\rightarrow$ IoU = **0.333333** (Esperado: 33.33%). $\rightarrow$ **APROVADO**.
4. **Máscara com Geometria Ausente (Buraco Interno):** Buraco de 100 px em área de 1600 px $\rightarrow$ IoU = **0.937500** (Esperado: 93.75%). Rachaduras internas detectadas = 100 px. $\rightarrow$ **APROVADO**.
5. **Cores Alteradas com Silhueta Idêntica:** Ref Vermelho vs Arb Verde $\rightarrow$ IoU = **1.000000**, RMSE = 0.8165 (Diferença cromática detectada com precisão). $\rightarrow$ **APROVADO**.

---

## 5. ETAPA 4 — INVESTIGAÇÃO E CORREÇÃO DO LOD MISTO

### 5.1 Reprodução do Cenário Limpo e Descoberta da Causa Raiz
Na primeira execução limpa da DAG automática sob o cenário misto (18.0m, Yaw 30°, Pitch 10°), a GPU selecionou 111 clusters de dois níveis distintos (`{ LOD 0: 35, LOD 1: 76 }`).
Contudo, o analisador de imagem detectou uma fenda de 217 pixels no topo da rocha.
- **Investigação Rastreou os Clusters Envolvidos:** O Grupo DAG 5 possui 5 clusters no LOD 1 (Clusters 253, 254, 255, 256, 257).
- A GPU selecionou os clusters 253, 256 e 257, mas **descartou os clusters 254 e 255**.
- **Causa Raiz Comprovada em `cull_clusters.glsl`:**
  As linhas 111 e 120 calculavam:
  ```glsl
  float p_dist = max(distance(ubo.camera_pos_fov.xyz, p_center) - radius, 0.01);
  float r_dist = max(distance(ubo.camera_pos_fov.xyz, r_center) - radius, 0.01);
  ```
  Ao subtrair o `radius` do cluster individual de uma métrica que pertence ao **grupo**, os clusters maiores (como 254 e 255) avaliavam uma distância menor, gerando projeção de erro de 1.506 px e 1.519 px (acima da tolerância de 1.5 px), enquanto seus irmãos menores avaliavam 1.47 px (abaixo da tolerância).
  Isso causou a ruptura da unidade do grupo, descartando 2 clusters e abrindo o buraco de 217 pixels!

### 5.2 Correção Cirúrgica Aplicada
Em `cull_clusters.glsl`, a distância para avaliação do erro de grupo foi corrigida para utilizar a distância homogênea ao centro do grupo:
```glsl
float p_dist = max(distance(ubo.camera_pos_fov.xyz, p_center), 0.01);
float r_dist = max(distance(ubo.camera_pos_fov.xyz, r_center), 0.01);
```

### 5.3 Resultado Pós-Correção
Após a correção:
- Todos os 5 clusters do Grupo 5 foram selecionados em bloco como unidade hermética.
- **IoU Verdadeiro:** saltou para **0.9974 (99.74%)**.
- **Buracos/Rachaduras Internas:** **0 pixels** (erradicação completa de fendas).

---

## 6. ETAPA 5 — RESULTADOS DA SUÍTE FINAL DE INDEPENDÊNCIA

A suíte executou a cena oficial `test_v5_1_final_validation.tscn` gerando evidências novas em uma única execução serial contínua:

### Resumo dos Testes A a F

| Teste | Descrição | Métrica Medida | Critério de Aceite | Resultado |
|---|---|---|---|---|
| **Teste A** | Desenho indireto ARBORIA desligado | Pixels Arb: 0 \| Ref: 107.996 | Arb == 0 px | **APROVADO** |
| **Teste B** | Referência convencional desligada | Pixels Arb: 107.996 \| Ref: 0 | Arb > 50.000 px, Ref == 0 | **APROVADO** |
| **Teste C** | Modelos geometricamente diferentes (Granite vs Dense Rock) | IoU: 0.1371 (13.71%) | IoU < 0.2500 | **APROVADO** |
| **Teste D** | Cor alterada somente na Referência (Vermelho vs Cinza) | IoU: 1.0000 \| RMSE: 0.6918 | IoU >= 0.995, RMSE > 0.40 | **APROVADO** |
| **Teste E (Caso 1)** | LOD Misto (18m, Yaw 30°, Pitch 10°) | 105 clusters (`{0: 17, 1: 88}`), IoU: 99.74% | IoU >= 98.0%, 0 rachaduras | **APROVADO** |
| **Teste E (Caso 2)** | LOD Misto Rotação (15m, Yaw 120°, Pitch 40°) | 130 clusters (`{0: 75, 1: 55}`), IoU: 99.96% | IoU >= 98.0%, 0 rachaduras | **APROVADO** |
| **Teste Visual 1** | Close-up 7.0m LOD 0 Unshaded | 444.068 px coincidentes, IoU: 100.00% | IoU >= 99.9%, RMSE == 0.0 | **APROVADO** |
| **Teste Visual 2** | Iluminação PBR Lit 12.0m | IoU: 100.00% \| RMSE: 0.0469 | RMSE <= 0.2000 | **APROVADO** |

---

## 7. ETAPA 6 — REGISTRO DO BLOQUEIO DE PROFUNDIDADE (FORWARD+)

### 7.1 Caso de Teste Mínimo Preservado
Foi executado o caso de teste em que um `BoxMesh` convencional do Godot (verde) foi posicionado à frente da rocha ARBORIA em Z = 5.5, enquanto o ARBORIA está em Z = 0.0 (Câmera em Z = 14.0).

### 7.2 Diagnóstico e Evidência
- O ARBORIA desenha diretamente na textura de cor do viewport via render pass próprio do `RenderingDevice`, utilizando um depth buffer D32_SFLOAT local (`vp_depth_tex`).
- Como o buffer de profundidade não é compartilhado com a passagem principal de geometria opaca do Godot Forward+, a rocha ARBORIA sobrescreveu 76.296 pixels da caixa frontal do Godot (`01_caso_a_godot_na_frente.png`).
- **Bloqueio Arquitetural Formalmente Registrado:** A composição visual entre ARBORIA e objetos nativos no Forward+ requer oclusão mútua nativa (composição via CompositorEffect, GDExtension ou Depth Pre-pass integrado), que será implementada na integração nativa.

---

## 8. TABELA FINAL OBRIGATÓRIA DA ORDEM TÉCNICA V5.1

| Requisito | Antes (Diagnóstico Inicial) | Depois (Correção V5.1) | Evidência | Status |
|---|---|---|---|---|
| **Captura independente** | Viewport compartilhado; vazamento de buffers e latência de 1 frame do SceneTree | SubViewports desacoplados com mundos 3D isolados e avanço estrito de frames | `negativos/teste_a_arboria_disabled.png`, `teste_b_ref_disabled.png` | **APROVADO** |
| **Buffers inicializados corretamente** | Sem limpeza de cor no draw_list; reutilização espúria de pixels de frames anteriores | `p_clear_color` com clear explícito de cor e profundidade na renderização isolada | `negativos/teste_a_arboria_disabled.png` (0 px retidos) | **APROVADO** |
| **IoU verdadeiro** | Proporção totalitária inválida `min/max` (informava 100% mesmo com interseção zero) | IoU verdadeiro formal ($\text{inter} / \text{union}$) com 5 testes unitários matemáticos | `scripts/vg_visual_metrics.gd`, `logs/execution.log` | **APROVADO** |
| **Testes negativos** | Sem cobertura de falhas reais ou com asserções fracas de console | 4 testes negativos (A, B, C, D) com asserções estritas que encerram com código de saída 1 em falha | `negativos/teste_c_diff.png`, `teste_d_diff.png` | **APROVADO** |
| **LOD misto** | DAG forçada em LOD 0 ou fenda de 217 px causada por perturbação de raio | Seleção DAG automática multi-nível ({0: 17, 1: 88} e {0: 75, 1: 55}) com distância coerente | `lod_misto/01_lod_misto_diff.png`, `02_lod_misto_rot_diff.png` | **APROVADO** |
| **Continuidade geométrica** | 217 pixels de buracos e fendas internas por quebra de corte no Grupo 5 | 0 pixels de buracos internos; continuidade hermética entre clusters | `lod_misto/01_lod_misto_diff.png` (IoU: 99.74%, 0 fendas) | **APROVADO** |
| **Profundidade Forward+** | Oclusão incorreta ocultada ou não diagnosticada | Caso mínimo reproduzido; bloqueio do buffer de profundidade isolado documentado | `profundidade/01_caso_a_godot_na_frente.png` | **BLOQUEIO CONHECIDO REGISTRADO** |

---

## 9. CONDIÇÃO DE ENCERRAMENTO

Todas as condições de encerramento da Ordem Técnica V5.1 foram cumpridas com sucesso:
1. Os testes visuais são comprovadamente independentes e rastreáveis byte a byte.
2. O cálculo de IoU foi formalizado matematicamente e validado com testes unitários.
3. Os testes negativos comprovaram a detecção de divergência e a eliminação de retenção de pixels.
4. O corte de LOD misto opera de forma contínua, hermética e com retenção de silhueta de 99.74%.
5. Todas as evidências e o manifesto JSON estão consolidados em `D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL\VALIDACAO_V5_1_FINAL`.
6. O bloqueio de profundidade foi rigorosamente documentado como pendência para a integração nativa.

**A Missão V5.1 está formalmente concluída.** Conforme determinado, o trabalho é interrompido aqui, sem início de novas funcionalidades ou fases posteriores.
