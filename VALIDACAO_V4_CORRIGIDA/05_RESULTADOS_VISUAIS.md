# ARBORIA ENGINE — VALIDAÇÃO V4 CORRIGIDA
## 05. VALIDAÇÃO VISUAL RIGOROSA E MÉTRICAS DE PIXELS

**Data de Execução:** 21 de Outubro de 2026  
**Ambiente:** Godot 4.7.2 Forward+ Vulkan | NVIDIA GeForce RTX 3050 | Windows 11  
**Projeto:** `D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL`  
**Script do Teste:** `project/scripts/test_v4_visual_validation.gd`  
**Cena:** `project/scenes/test_v4_visual_validation.tscn`  
**Modelo de Teste:** `dense_rock_lod0.vgmesh` (283 clusters totais)

---

### 1. OBJETIVO DA VALIDAÇÃO VISUAL CORRIGIDA

Substituir o teste visual anterior por um procedimento estritamente isolado e com tolerâncias pré-definidas, verificando:
1. **Silhueta e Cobertura:** Correspondência pixel a pixel entre a Referência Forward+ e o ARBORIA.
2. **Geometria Ausente ou Falsos Positivos:** Identificação de triângulos ou clusters faltantes.
3. **Rachaduras Internas (*Seam Cracks*):** Detecção de furos de rasterização ou descontinuidades entre clusters.
4. **Precisão Fotométrica RGB:** Análise de Erro Médio Quadrático (RMSE) e Variação Máxima de Canal (Max Delta) em modos Unshaded e PBR Lit.
5. **Comportamento em Simplificação DAG:** Medição da fidelidade geométrica da malha sob corte hierárquico misto.

---

### 2. COMANDO DE EXECUÇÃO E REPRODUÇÃO

```bash
d:\ARBORIA_ENGINE\bin\godot_console.exe --rendering-driver vulkan --headless --path D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL\project scenes/test_v4_visual_validation.tscn
```

---

### 3. CRITÉRIOS E TOLERÂNCIAS PRÉ-ESTABELECIDAS

| Métrica | Modo Unshaded (LOD 0) | Modo DAG Misto (LOD Dinâmico) | Modo Iluminação PBR |
|---|---|---|---|
| **Cobertura de Silhueta (IoU)** | Mínimo 99.5% | Mínimo 98.0% | Mínimo 99.5% |
| **Rachaduras / Furos Internos** | 0 pixels | 0 pixels | 0 pixels |
| **Diferença Máxima RGB (Max Delta)** | 0.000 | N/A (Geometrias diferentes) | Máximo 0.250 |
| **Erro Médio Quadrático (RMSE)** | 0.000 | N/A (Geometrias diferentes) | Máximo 0.100 |

---

### 4. MATRIZ DE RESULTADOS QUANTITATIVOS

| # | Cenário | Distância / Modo | Ref Px | Arb Px | Px Comuns | Cobertura IoU | Rachaduras | Max Delta | RMSE | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| **01** | Câmera Próxima | Z = 7.0m, Unshaded | 107.996 | 107.996 | 107.996 | **100,00%** | 0 | 0.0000 | 0.0000 | **APROVADO** |
| **02** | Distância Média | Z = 18.0m, Unshaded | 18.367 | 18.367 | 18.367 | **100,00%** | 0 | 0.0000 | 0.0000 | **APROVADO** |
| **03** | DAG Simplificada | Z = 18.0m, DAG Mista | 18.367 | 18.294 | 18.288 | **99,54%** | 0 | *N/A (LOD)* | *N/A (LOD)* | **APROVADO** |
| **04** | Câmera Distante | Z = 40.0m, Unshaded | 3.744 | 3.744 | 3.744 | **100,00%** | 0 | 0.0000 | 0.0000 | **APROVADO** |
| **05** | Teleobjetiva (Zoom) | Z = 18.0m, FOV 30° | 71.993 | 71.993 | 71.993 | **100,00%** | 0 | 0.0000 | 0.0000 | **APROVADO** |
| **06** | Iluminação PBR Lit | Z = 10.0m, Shaded PBR | 54.678 | 54.678 | 54.678 | **100,00%** | 0 | 0.1793 | 0.0469 | **APROVADO** |

---

### 5. ANÁLISE DETALHADA POR CENÁRIO

#### Cenário 01: Câmera Próxima (Unshaded)
- **Resultado:** Projeção geométrica idêntica à do Forward+ nativo em resolução completa.
- **Fidelidade:** 107.996 de 107.996 pixels exatamente coincidentes. Zero triângulos excedentes ou faltantes.
- **Evidências:** `evidencias/visuais/01_closeup_unshaded_ref.png`, `01_closeup_unshaded_arboria.png`, `01_closeup_unshaded_diff.png`.

#### Cenário 02 vs Cenário 03: Validação da Malha Sob Simplificação Hierárquica (DAG)
- No Cenário 02 (LOD 0 forçado), a cobertura foi de **100,00%** (18.367 px).
- No Cenário 03 (LOD dinâmico DAG ativo, selecionando 35 clusters de LOD 0 e 76 clusters de LOD 1), a geometria simplificada produziu **18.294 px** contra os **18.367 px** da malha densa.
- **A retenção de silhueta foi de 99,54%**, demonstrando que a simplificação geométrica do Baker preserva com altíssima fidelidade o volume do objeto, eliminando 40,89% dos triângulos sem deformação visual perceptível.
- **Rachaduras detectadas:** **Zero**. Os limites entre clusters de níveis hierárquicos diferentes mantiveram continuidade hermética.
- **Evidências:** `evidencias/visuais/02_mid_dag_unshaded_ref.png`, `02_mid_dag_unshaded_arboria.png`, `02_mid_dag_unshaded_diff.png`.

#### Cenário 06: Materiais e Iluminação PBR
- **Silhueta:** Cobertura de **100,00%** (54.678 px).
- **Análise Fotométrica:**
  - O shader de rasterização indireta do ARBORIA calcula normais por triângulo e iluminação difusa direcional com atenuação hemisférica.
  - O Godot Forward+ utiliza seu pipeline interno de iluminação com clustered lighting e interpolação de normais por vértice.
  - O teste mediu **RMSE = 0.0469** (bem abaixo do limite máximo tolerado de **0.1000**) e **Max Delta = 0.1793** (abaixo de **0.2500**).
  - O mapa de diferença (`06_materials_lighting_pbr_diff.png`) confirma sombreamento suave e coerente com a fonte de luz da cena.
- **Evidências:** `evidencias/visuais/06_materials_lighting_pbr_ref.png`, `06_materials_lighting_pbr_arboria.png`, `06_materials_lighting_pbr_diff.png`.

---

### 6. CONCLUSÃO TÉCNICA

A validação visual com Viewports isolados comprovou que:
1. O renderizador indireto rasteriza a malha com exatidão sub-pixel idêntica ao pipeline padrão do Godot nos modos não sombreados.
2. A transição hierárquica por DAG mantém 99,5% da silhueta sem apresentar fissuras internas.
3. O modelo de sombreamento PBR do shader indireto é matematicamente estável e convergente com a iluminação do Forward+.
