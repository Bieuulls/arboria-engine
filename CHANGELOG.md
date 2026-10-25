# Changelog

Todas as alterações notáveis no projeto **ARBORIA ENGINE** serão documentadas neste arquivo.

O formato segue as diretrizes do [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/) e este projeto adere ao [Versionamento Semântico](https://semver.org/lang/pt-BR/).

---

## [0.2.0] - 2026-10-25

### Adicionado
- **Projeção de Sombras Direcionais (FASE 3.1):** Adicionado proxy interno `GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY` em `ArboriaInstance3D`, permitindo que malhas virtualizadas projetem sombras dinâmicas completas no Shadow Atlas e Cascaded Shadow Maps (CSM) do Godot Forward+.
- **Compatibilidade PBR StandardMaterial3D (FASE 3.2):** Implementada propriedade `material_override: StandardMaterial3D` em `ArboriaInstance3D` com sincronização automática de Albedo, Normal Texture, Roughness, Metallic, Specular e UV Scale.
- **Suíte de Testes Expandida (FASE 4.1):** 27 testes automatizados executáveis via CLI (`tests/panel/panel.py --cli`), incluindo testes de regressão de neutralização de caminhos locais e integridade hierárquica.
- **CI Local Unificado (FASE 4.2):** Scripts `ci_local.bat` e `ci_local.ps1` executando compilação C++, testes CTest, 27 testes do painel, benchmark rápido e verificação de caminhos locais com código de saída determinístico.
- **Feedback Loop com Telemetria Real em arboria_ai (FASE 4.3):** Eliminação de qualquer dado sintético ou mock no módulo `tools/extras/arboria_ai/`, alimentando prompts e métricas AEOC diretamente de `bench/results/raw.csv` e `bench/results/summary.md`.
- **Documentação de Proveniência e Licenças de Assets (FASE 5.3):** Criação de `assets/README.md` detalhando proveniência procedural e dedicação ao Domínio Público (CC0 1.0 Universal) de todas as malhas do projeto.

### Corrigido & Otimizado
- **Neutralização de Caminhos Locais (FASE 0.2):** Remoção de todos os caminhos absolutos locais de desenvolvimento em todo o código rastreado do repositório.
- **Paridade de Primitivas no Baseline (FASE 0.1):** Ajuste de frustum orbital e contagem exata de triângulos eliminando divergências entre `MeshInstance3D` e `MultiMeshInstance3D`.
- **Submissão Unificada (FASE 1.1):** Pipeline de submissão unificado para 1 dispatch de compute e 1 draw indirect global O(1) independente do número de instâncias.
- **Avaliação de Clusters sem Recursão Bloqueante (FASE 1.2):** Shader de culling atualizado para avaliação linear e remoção de laços infinitos na GPU.
- **buffer_get_data Síncrono no Render Loop (FASE 1.4):** Substituição de leituras bloqueantes no meio do frame por amostragem via ring-buffer e fallback assíncrono.

---

## [0.1.0] - 2026-10-23

### Adicionado
- **Core Virtual Geometry (Nanite-like DAG):** Implementação completa em C++ nativo e Compute Shaders Forward+ Vulkan 1.4.
- **Submissão GPU Global $O(1)$:** Despacho único de compute e desenho indireto consolidado, escalando de 1 a mais de 2.000 instâncias sem aumentar contagem de submissões na CPU.
- **Hierarchical Z-Buffer (Hi-Z):** Pirâmide hierárquica conservadora com Reversed-Z depth prepass, descartando clusters e instâncias ocluídos antes do rasterizador.
- **Integração Jolt Physics 3D Real:**
  - Suporte completo a colisores côncavos (trimesh LOD 0), convexos e caixas.
  - Cache de `Shape3D` global evitando duplicação de colisores idênticos na memória.
  - Sincronização automática entre transformações de `RigidBody3D` e a GPU Scene.
  - Otimização de repouso (*dirty caching* quando corpos entram em estado `sleeping`).
- **Baker CLI C++:** Utilitário nativo de conversão de modelos Wavefront `.obj` para `.vgmesh` binário com clusterização de triângulos e bounds convexos via Meshoptimizer.
- **Efeitos de Compositor Forward+:** `ArboriaCompositorEffect` com suporte a `PRE_OPAQUE` (Depth Prepass) e `POST_OPAQUE` (Main Raster).
- **Materiais PBR Completos:** Cook-Torrance GGX, difusa Lambertiana com conservação de energia, albedo, normal mapping, roughness, metallic, emissão e alpha cutout.
- **Bateria de Testes Automatizados e Benchmarks Físicos:**
  - Testes A a F de física real no Jolt (gravidade, caixas, rochas convexas, character controller com rampas e empurrão, CCD em velocidades ultra-altas e juntas físicas).
  - Suíte de benchmark reproduzível comparando Jolt Physics vs GodotPhysics3D.

### Corrigido
- Eliminados erros de `uniform_set is null` através de invalidação sob demanda na realocação de buffers.
- Eliminadas leituras bloqueantes recorrentes na renderização via amostragem assíncrona de telemetria.
- Eliminados vazamentos de RIDs de textura, buffers e pipelines no fechamento de cenas.
