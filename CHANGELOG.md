# Changelog

Todas as alterações notáveis no projeto **ARBORIA ENGINE** serão documentadas neste arquivo.

O formato segue as diretrizes do [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/) e este projeto adere ao [Versionamento Semântico](https://semver.org/lang/pt-BR/).

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
