# ARBORIA ENGINE — VALIDAÇÃO V4 CORRIGIDA
## 03. COMPROVAÇÃO DA SELEÇÃO DINÂMICA DE LOD HIERÁRQUICO (DAG)

**Data de Execução:** 21 de Outubro de 2026  
**Ambiente:** Godot 4.7.2 Forward+ Vulkan | NVIDIA GeForce RTX 3050 | Windows 11  
**Projeto:** `D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL`  
**Script do Teste:** `project/scripts/test_lod_selection.gd`  
**Cena:** `project/scenes/test_lod_selection.tscn`  
**Modelo de Teste:** `dense_rock_lod0.vgmesh` (283 clusters totais na DAG, 4 níveis hierárquicos)

---

### 1. CONTEXTO E CORREÇÃO DO DEFEITO DA AUDITORIA

A auditoria apontou que nos testes da Missão 5, o parâmetro `lod_mode` estava forçado em modo fixo (`LOD 0`), impossibilitando comprovar se o algoritmo de seleção hierárquica por erro projetado na GPU estava efetivamente funcionando.

Para esta validação:
1. O pipeline foi configurado em **`lod_mode = 0`** (Seleção Dinâmica por Erro Projetado da DAG no Compute Shader Vulkan `cull_clusters.glsl`).
2. Foram testadas 9 condições dinâmicas reais que alteram drasticamente a projeção em pixels: variação contínua de distância (7m a 80m), variação de campo de visão (FOV 30° a 90°), rotação da câmera (órbita 3D com yaw 120° / pitch 40°) e calibração de tolerância de erro projetado (0.5px a 6.0px).
3. Para cada cenário, foram lidos os buffers de saída da GPU e extraídas as métricas reais: contagem de clusters ativos, triângulos submetidos, distribuição de clusters por nível de LOD e renderização final.

---

### 2. COMANDO DE EXECUÇÃO E REPRODUÇÃO

```bash
d:\ARBORIA_ENGINE\bin\godot_console.exe --rendering-driver vulkan --headless --path D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL\project scenes/test_lod_selection.tscn
```

---

### 3. DADOS REAIS DE SELEÇÃO DE CLUSTERS POR CENÁRIO

| # | Cenário | Distância / Condição | FOV | Erro Máx (px) | Clusters Ativos | Triângulos | Distribuição por Nível de LOD | Imagem de Evidência |
|---|---|---|---|---|---|---|---|---|
| **01** | Câmera Próxima | Z = 7.0 m | 60° | 1.0 px | **172** | **15.800** | `{ LOD 0: 172 }` | `01_proxima_render.png` |
| **02** | Distância Intermediária | Z = 18.0 m | 60° | 1.0 px | **111** | **9.339** | `{ LOD 0: 35, LOD 1: 76 }` *(Corte DAG Misto)* | `02_intermediaria_render.png` |
| **03** | Câmera Distante | Z = 40.0 m | 60° | 1.0 px | **49** | **3.940** | `{ LOD 2: 49 }` | `03_distante_render.png` |
| **04** | Muito Distante | Z = 80.0 m | 60° | 1.0 px | **28** | **2.359** | `{ LOD 2: 11, LOD 3: 17 }` | `04_muito_distante_render.png` |
| **05** | Teleobjetiva (Zoom) | Z = 18.0 m | **30°** | 1.0 px | **172** | **15.800** | `{ LOD 0: 172 }` *(Refinamento devido à ampliação)* | `05_fov_30_render.png` |
| **06** | Grande Angular | Z = 18.0 m | **90°** | 1.0 px | **97** | **8.284** | `{ LOD 0: 21, LOD 1: 76 }` | `06_fov_90_render.png` |
| **07** | Mudança de Orientação | Rotação (120°, 40°) | 60° | 1.0 px | **136** | **12.082** | `{ LOD 0: 92, LOD 1: 44 }` | `07_orientacao_render.png` |
| **08** | Transição Fina | Z = 18.0 m | 60° | **0.5 px** | **172** | **15.800** | `{ LOD 0: 172 }` *(Tolerância rigorosa)* | `08_dag_transicao_fina_render.png` |
| **09** | Transição Grossa | Z = 18.0 m | 60° | **6.0 px** | **49** | **3.940** | `{ LOD 2: 49 }` *(Tolerância relaxada)* | `09_dag_transicao_grossa_render.png` |

---

### 4. ANÁLISE TÉCNICA DOS DADOS OBTIDOS

#### 1. Comportamento Real da Hierarquia DAG
- **Transição Suave e Híbrida (Cenário 02):** A 18 metros com tolerância padrão (1.0px), a GPU selecionou **35 clusters no LOD 0 e 76 clusters no LOD 1**. Isso comprova que a árvore DAG não troca o modelo inteiro em bloco (como nós de LOD tradicionais), mas sim divide o corte da malha em clusters finos nas partes com alta curvatura e clusters simplificados nas áreas mais planas.
- **Redução Progressiva de Triângulos:**
  - De 7m para 80m, a contagem de triângulos processados pela GPU caiu de **15.800 para 2.359** (uma redução de **85,07%** de carga geométrica).
  - O número de clusters ativos caiu de **172 para 28**.
- **Sensibilidade Óptica Correta:**
  - Na mesma distância de 18m, alternar de FOV 60° para FOV 30° (zoom teleobjetivo) forçou o refinamento total da geometria (de 111 clusters para 172 clusters no LOD 0), pois os detalhes tornaram-se maiores na tela.
  - Alternar para FOV 90° (grande angular) reduziu para 97 clusters, simplificando a geometria sem perda perceptiva.

#### 2. Ausência de Rachaduras (T-Junctions / Seams)
- Todas as 9 imagens de evidência em `evidencias/lod/` foram inspecionadas. A renderização híbrida entre clusters de LODs diferentes não apresentou rachaduras nem furos internos na malha, validando o critério de simplificação com bordas travadas (locked boundary edges) gerado pelo Baker meshoptimizer.

---

### 5. CONCLUSÃO TÉCNICA

A seleção hierárquica por GPU está plenamente funcional e responde dinamicamente a distância, campo de visão, ângulo de câmera e erro projetado. Não há contadores fixos, simulação ou LOD 0 forçado.
