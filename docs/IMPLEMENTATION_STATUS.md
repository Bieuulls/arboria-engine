# ARBORIA ENGINE — STATUS OFICIAL DE IMPLEMENTAÇÃO E EXECUÇÃO

**Projeto:** `D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL`  
**Motor:** Godot 4.7.2 Forward+ / Vulkan 1.4  
**Hardware de Validação:** NVIDIA GeForce RTX 3050 Laptop GPU (6 GB VRAM) / Windows 11  
**Branch de Desenvolvimento:** `arboria/renderer-completion`  
**Data de Início:** 22/10/2026  

---

## 1. Tabela de Controle de Etapas

| Etapa | Descrição | Status | Commit | Arquivos Alterados | Testes / Comprovação | Pendências Verificáveis |
| :---: | :--- | :---: | :---: | :--- | :--- | :--- |
| **0** | **Proteger a Base e Corrigir Medições** | ✅ **APROVADO** | `98deecf` | `bench/runner.py`, `project/bench/benchmark_scene.gd`, `project/scripts/arboria_native_pipeline.gd`, `bench/config.json` | 8 combinações x 1000 frames validadas, zero vitórias fictícias, métricas GPU/CPU/Clusters/Tris instrumentadas | Nenhuma |
| **1** | **Corrigir Camada Nativa C++ e ABI** | 🔄 *Em Execução* | Pendente | `native/renderer/integration/*`, `native/renderer/core/*` | Teste CTest de ciclo de vida (registros, updates, releases repetidos sem memory leak) | Eliminar buffers improvisados de 32 bytes, adotar bindings tipados e API estrita |
| **2** | **Construir o GPU Scene Global** | ⏳ *Pendente* | - | `ArboriaRenderWorld`, `ArboriaGPUScene`, shaders GLSL | 1, 80, 500, 2000 instâncias sem submissão 1:1, dispatches e draws agrupados | Múltiplos draws indiretos agrupados em buffers globais |
| **3** | **Integração Completa ao Forward+** | ⏳ *Pendente* | - | Compositor / Fork Vulkan Forward+, Shaders | Depth prepass com Reversed-Z, sombras Directional/Omni/Spot, oclusão mista | Geometria ARBORIA projetando e recebendo sombras |
| **4** | **Materiais PBR e Qualidade Visual** | ⏳ *Pendente* | - | Shaders PBR, Baker de materiais | Teste lado a lado com StandardMaterial3D (Albedo, Normal, Roughness, Metalness, Cutout) | Suporte completo de texturas e UVs sem perda em troca de LOD |
| **5** | **Refinar o DAG e Eliminar Defeitos Geométricos** | ⏳ *Pendente* | - | Baker DAG, Shaders de seleção | Testes automatizados de cracks, T-junctions e pixel error | Continuidade estrita entre clusters de níveis adjacentes |
| **6** | **Hierarchical Z-Buffer (Hi-Z) Real** | ⏳ *Pendente* | - | Hi-Z generator compute, culling shader | Redução mensurável de clusters em cenas oclusas com Hi-Z ligado vs desligado | Pirâmide de profundidade conservadora conectada ao frame |
| **7** | **Gerenciamento Real de VRAM e Streaming** | ⏳ *Pendente* | - | GPU Memory Manager, Streaming Manager, `.vgmesh` pages | Carregamento assíncrono de disco sob orçamento de VRAM sem estourar pool | Eviction LRU e fallback de páginas para LOD residente |
| **8** | **Importação Real e Ferramentas de Editor** | ⏳ *Pendente* | - | `VirtualMeshInstance3D`, Editor Plugins, Asset Importer | Importação GLB/OBJ -> Baker -> `.vgmesh` -> Inspector | Inspector com visualização de bounds, clusters e fallbacks explícitos |
| **9** | **Benchmark Profissional Final** | ⏳ *Pendente* | - | `bench/` suite completa | 1920x1080, VSync OFF, 300 warmup, 1000 medidos nas 7 cenas obrigatórias | Comparação honesta de frame time p50/p95/p99 e VRAM real |
| **10** | **Estabilidade, Gameplay e Entrega** | ⏳ *Pendente* | - | Cenas interativas de gameplay | Teste de estresse contínuo de 20 minutos com câmera livre e streaming | Integração com colisões, navegação e zero vazamentos |

---

## 2. Registro de Commits na Branch `arboria/renderer-completion`

1. `Etapa 0`: feat(etapa-0): proteger base, preservar benchmarks históricos e corrigir telemetria/critérios de medição

