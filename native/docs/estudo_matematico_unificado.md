# ARBORIA ENGINE — FORMULAÇÃO MATEMÁTICA E ARQUITETURA DE CLUSTER LOD
## ESTUDO COMPARATIVO E UNIFICAÇÃO TÉCNICA (NVIDIA VK_LOD_CLUSTERS + ZEUS + SCTHE)

**PROJETO:** `D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL`  
**DATA:** 2026-10-22  
**ALVO:** Forward+ Vulkan 1.4 / NVIDIA RTX (Arquitetura Ampere/Ada/Blackwell)  
**IDENTIFICADOR DE RASTREABILIDADE:** `ARB-MATH-V7-2026`

---

## 1. REPOSITÓRIOS E PESQUISAS DE REFERÊNCIA ESTUDADOS

Para construir o núcleo de geometria virtualizada mais veloz e matematicamente rigoroso no Godot/Vulkan, analisamos 4 referências abertas de ponta:

1. **`nvpro-samples/vk_lod_clusters` (NVIDIA Corporation):**
   - *Foco:* Implementação em nível de driver Vulkan para rasterização contínua de clusters com travessia de hierarquia GPU e streaming massivo.
   - *Contribuição para o ARBORIA:* A arquitetura de `traversal.glsl` e `stream_setup.comp.glsl`, gerenciamento de buffers indiretos compactos e prevenção de divergência de warp (32 threads alinhadas).
2. **`Scthe/nanite-webgpu` (Marcin Matuszczyk):**
   - *Foco:* Engenharia reversa didática e precisa do pipeline Nanite da Epic Games.
   - *Contribuição para o ARBORIA:* Projeção perspectiva de erro esférico, dual-condition de ativação de cluster DAG e estrutura limpa de dados compactados.
3. **`zeux/meshoptimizer` / `clusterlod.h` (Arseny Kapoulkine):**
   - *Foco:* O algoritmo padrão da indústria de particionamento de malhas em meshlets de 64/128 triângulos e cálculo de erro por Quadric Error Metric (QEM) com preservação de bordas fixas.
   - *Contribuição para o ARBORIA:* Bounds esféricos hierárquicos e métricas de cone normal (Backface Cone Culling).
4. **`bcrusco/Hierarchical-Z-Buffer-Occlusion-Culling`:**
   - *Foco:* Construção de pirâmides mipmap de profundidade (Hi-Z) e teste de oclusão de bounding boxes no compute shader.
   - *Contribuição para o ARBORIA:* Cálculo do Mip Level ideal da pirâmide e amostragem bilinear footprint $2 \times 2$.

---

## 2. O MODELO MATEMÁTICO UNIFICADO DO ARBORIA (`ARB-MATH`)

### 2.1. Projeção Perspectiva de Erro de Tela (Screen-Space Error)

Dado um cluster ou grupo com centro $\mathbf{C} \in \mathbb{R}^3$, raio de delimitação $R_{bound} \in \mathbb{R}$ e erro geométrico em espaço de objeto $\epsilon_{mesh} \in \mathbb{R}^+$:

A distância euclidiana da câmera $\mathbf{P}_{cam}$ ao centro é:
$$d = \|\mathbf{C} - \mathbf{P}_{cam}\|_2$$

Para evitar divisões por zero ou singularidades dentro da esfera de delimitação, a distância efetiva mínima é:
$$d_{eff} = \max(d - R_{bound}, \, z_{near})$$

O fator de projeção da câmera baseado no campo de visão vertical ($FOV$) e na altura do viewport em pixels ($H_{vp}$):
$$K_{proj} = \frac{H_{vp}}{2 \cdot \tan\left(\frac{FOV}{2}\right)}$$

O erro projetado em pixels na tela ($\epsilon_{screen}$) é dado por:
$$\epsilon_{screen} = \frac{\epsilon_{mesh} \cdot K_{proj}}{d_{eff}}$$

---

### 2.2. O Critério Dual de Corte na DAG Nanite (Cut-Condition)

Para garantir que a superfície resultante seja uma variedade contínua (manifold) **sem buracos (cracks) e sem triângulos duplicados**, cada cluster avalia um critério de corte restrito baseado em seu erro e no erro de seu grupo pai:

Seja $\tau$ o limite máximo de erro tolerado em pixels (`max_screen_error`, padrão $1.5$ px):

1. **Condição do Grupo Pai (Parent):** O erro do agrupamento pai deve ser **inaceitável** na distância atual (ou seja, requer maior detalhe):
   $$\epsilon_{parent\_screen} > \tau$$
   *(Se o pai tiver erro menor ou igual a $\tau$, o pai é quem deveria ser desenhado, descartando seus filhos).*

2. **Condição do Cluster Local (Self):** O erro do cluster atual deve ser **aceitável** na distância atual:
   $$\epsilon_{cluster\_screen} \le \tau$$
   *(Se o cluster tiver erro maior que $\tau$, ele é muito grosseiro e deve ser refinado pelo grupo filho).*

Portanto, a função booleana fundamental de ativação $A(C)$ de um cluster é:
$$\boxed{A(C) = (\epsilon_{parent\_screen} > \tau) \land (\epsilon_{cluster\_screen} \le \tau)}$$

Esta fórmula matemática garante monotonicidade absoluta na travessia da árvore.

---

### 2.3. Backface Cone Culling Vetorial

Cada cluster possui um cone de normais definido por um vetor diretor normal médio normalizado $\hat{\mathbf{N}} \in \mathbb{R}^3$ e um semi-ângulo de abertura $\theta \in [0, \pi]$. Armazenamos compactamente o vetor $\mathbf{V}_{cone} = (\hat{N}_x, \hat{N}_y, \hat{N}_z, -\cos(\theta + \frac{\pi}{2})) = (\hat{\mathbf{N}}, \sin\theta)$.

Seja o vetor de visão da câmera apontando para o centro da esfera do cluster:
$$\mathbf{V}_{view} = \mathbf{C} - \mathbf{P}_{cam}, \quad \hat{\mathbf{V}}_{view} = \frac{\mathbf{V}_{view}}{\|\mathbf{V}_{view}\|}$$

O cluster é **completamente invisível por estar de costas para a câmera (backfacing)** se todos os seus triângulos apontarem para longe:
$$\boxed{\hat{\mathbf{N}} \cdot \hat{\mathbf{V}}_{view} > \sin\theta + \frac{R_{bound}}{\|\mathbf{V}_{view}\|}}$$

---

### 2.4. Hierarchical Z-Buffer Occlusion Culling (Hi-Z para Reversed-Z)

No contrato Vulkan Forward+ com profundidade invertida (Reversed-Z):
- Near plane: $Z = 1.0$
- Far plane / Sky: $Z = 0.0$
- Operador de teste: `GREATER_OR_EQUAL`
- Construção da Pirâmide Hi-Z: cada nível $Mip_{k+1}$ armazena o **mínimo** dos $2 \times 2$ texels do nível $Mip_k$:
  $$D_{parent}(x, y) = \min \begin{pmatrix} D(2x, 2y), & D(2x+1, 2y) \\ D(2x, 2y+1), & D(2x+1, 2y+1) \end{pmatrix}$$

#### Teste do Cluster contra o Hi-Z:
1. Projetar os 8 vértices da AABB do cluster em espaço de tela normalizado (NDC $[0, 1] \times [0, 1]$).
2. Determinar a bounding box em pixels na tela: $[x_{min}, x_{max}] \times [y_{min}, y_{max}]$ e o $Z_{max}$ do cluster (o ponto mais próximo da câmera, ou seja, o maior valor de Z no espaço Reversed-Z).
3. Calcular a dimensão máxima em pixels da projeção:
   $$size = \max(x_{max} - x_{min}, \, y_{max} - y_{min})$$
4. Determinar o nível de mipmap da pirâmide Hi-Z tal que a bounding box cubra no máximo uma pegada de $2 \times 2$ texels:
   $$L = \max\left(0, \, \lceil \log_2(size) \rceil\right)$$
5. Fazer a leitura de profundidade $Z_{hiz}$ no nível $L$ cobrindo a área da bounding box.
6. **Critério de Oclusão:** Se o ponto mais próximo do cluster ($Z_{max}$) estiver mais distante da câmera que a profundidade armazenada na pirâmide ($Z_{hiz}$), o cluster está **completamente oculto**:
   $$\text{Se } Z_{max} < Z_{hiz} \implies \text{DESCARTAR CLUSTER}$$

---

## 3. MAPA DE IMPLEMENTAÇÃO E RASTREABILIDADE NO ARBORIA

| Componente Matemático | Arquivo no Projeto | Símbolo / Função |
|---|---|---|
| **Métrica de Projeção $K_{proj}$** | `cull_clusters.glsl` | `ARB_GPU_ProjectScreenError()` |
| **Dual Cut-Condition $A(C)$** | `cull_clusters.glsl` | `ARB_GPU_EvaluateDAGCut()` |
| **Backface Cone Test** | `cull_clusters.glsl` | `ARB_GPU_TestConeCull()` |
| **Hi-Z Downsample Pyramid** | `shaders/hiz_downsample.glsl` *(novo)* | `ARB_GPU_BuildHiZLevel()` |
| **Hi-Z Occlusion Test** | `cull_clusters.glsl` | `ARB_GPU_TestHiZOcclusion()` |
| **Submissão C++ Nativa** | `vg_indirect_renderer.cpp` | `Arboria::VGIndirectRenderer::dispatch()` |
