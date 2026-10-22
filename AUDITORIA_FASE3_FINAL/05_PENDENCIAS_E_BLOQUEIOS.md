# RELATÓRIO 05 — PENDÊNCIAS E BLOQUEIOS TÉCNICOS
**Data:** 21 de Outubro de 2026  
**Diretório:** `D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL`  
**Responsável:** Engenheiro de Renderização (ARBORIA ENGINE Core)

---

## 1. BLOQUEIOS ARQUITETURAIS IDENTIFICADOS

### Bloqueio B1: Injeção Nativa de Desenho Indireto no Forward+ do Godot 4
- **Classificação:** `BLOQUEADO — REQUER INTEGRAÇÃO NATIVA (GDEXTENSION / C++)`
- **Diagnóstico Técnico:**
  1. A API de alto nível do Godot 4 (GDScript / SceneTree) rasteriza geometria através de nós como `MeshInstance3D` e `MultiMeshInstance3D`.
  2. O método `rd.draw_list_draw_indirect()` funciona perfeitamente em um `RenderingDevice` local (comprovado nos testes negativos com 100% de sucesso), desenhando a geometria real do `.vgmesh` diretamente de `VkDrawIndirectCommand`.
  3. No entanto, para que o desenho indireto escreva diretamente no **G-Buffer de Profundidade e Opacidade do viewport principal da cena do Godot** (usufruindo de Sombras Direcionais, SSAO, SSR, Glow e SDFGI nativos sem passar por `MultiMeshInstance3D`), o Godot 4 exige um hook em nível de motor.
  4. Em GDScript puro, a cena principal é alimentada pelo `MultiMeshInstance3D` com o shader `vg_cluster_render.gdshader` (Vertex Pulling), onde a GPU escreve a seleção na textura e o Vertex Shader decodifica os clusters.
- **Proposta Técnica Mínima (Sem Fork do Motor):**
  - Implementar uma **GDExtension em C++** que utilize a API `CompositorEffect` (introduzida no Godot 4.3+) com flag de execução em `EFFECT_CALLBACK_TYPE_PRE_OPAQUE` ou custom rasterizer hook.
  - A GDExtension terá acesso aos ponteiros Vulkan nativos (`VkCommandBuffer`, `VkBuffer`, `vkCmdDrawIndirect`) do RenderDevice primário do Godot, permitindo submeter o `VkDrawIndirectCommand` no mesmo pipeline gráfico da cena sem intermediários.
  - **Status:** Não implementado nesta fase para respeitar a Regra 6 e Regra 7 do contrato inegociável (aguardando aprovação de escopo nativo).

---

## 2. LIMITAÇÕES DE MEDIÇÃO E TELEMETRIA

### Limitação L1: Medição de Rasterização GPU Isolada da Cena
- **Diagnóstico:**
  O Godot 4 permite criar queries de timestamps em `RenderingDevice` para Compute Shaders e Draw Lists customizadas (como demonstrado pelo nosso medidor que capturou 0.029 ms de compute time). No entanto, o tempo de rasterização da passagem Forward+ principal da cena é gerenciado internamente pelo `RendererSceneRenderImplementation` e não expõe timestamps individuais de DrawPass ao GDScript.
- **Tratamento:** Registrado honestamente como **`NÃO MEDIDO`**, em estrita observância à proibição de métricas simuladas.

### Limitação L2: Consumo de Memória de Heap Vulkan do Sistema Operacional
- **Diagnóstico:**
  A memória nominal alocada pelo ARBORIA (1.693 KB para `dense_rock_test.vgmesh`) é calculada a partir dos bytes exatos dos buffers e texturas criados no Vulkan. O consumo real de heap e paginação de driver (VRAM OS total) varia dinamicamente de acordo com a fragmentação do driver da NVIDIA e exige ferramentas externas (como NVIDIA Nsight Graphics ou RenderDoc).
- **Tratamento:** Registrado honestamente como **`NÃO MEDIDO (Requer Nsight/RenderDoc externo)`**.

---

## 3. PENDÊNCIAS RESTANTES ANTES DA FASE 4

1. **Geração de Malhas Megageométricas (> 1.000.000 de triângulos):**
   Os modelos atualmente presentes no repositório possuem até 35.000 triângulos (`pine_trunk_complex`). O Baker e o pipeline foram validados com 100% de sucesso nessa escala. O teste com malhas acima de 1 milhão de triângulos necessita de assets de alta densidade (arquivos OBJ de ~150-200 MB) para teste de estresse de memória e clusterização DAG em larga escala.
2. **Ordenação Determinística de Clusters:**
   O uso de `atomicAdd` em `cull_clusters.glsl` assegura reserva atômica exclusiva de slots, mas a ordem em que as threads GPU chegam ao `atomicAdd` depende do escalonador de warps do hardware. Para geometria opaca com Z-Buffer (`COMPARE_OP_LESS_OR_EQUAL`), a ordem de chegada é indiferente. Para geometria semitransparente, será necessário um algoritmo de ordenação (ex: Radix Sort GPU) na Fase 4.
