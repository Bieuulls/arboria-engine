# ARBORIA ENGINE — Virtual Geometry for Godot 4 (Forward+ / Vulkan 1.4)

[![Godot Engine](https://img.shields.io/badge/Godot-4.7%2B-blue.svg)](https://godotengine.org/)
[![Vulkan](https://img.shields.io/badge/Graphics-Vulkan%201.4%20Forward%2B-red.svg)](https://www.vulkan.org/)
[![Physics](https://img.shields.io/badge/Physics-Jolt%20Physics%203D-orange.svg)](https://github.com/godot-jolt/godot-jolt)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**ARBORIA ENGINE** é um complemento de geometria virtualizada de alto desempenho (*Cluster-based Continuous Level of Detail / Nanite-like DAG*) para **Godot 4.7+ Forward+**.

Ele permite instanciar e renderizar cenários densos contendo dezenas de milhões de triângulos com **submissão GPU constante $O(1)$** (1 Compute Dispatch e 1 Draw Indireto independente da quantidade de instâncias), *Hierarchical Z-Buffer (Hi-Z) Occlusion Culling* em hardware, *Depth Prepass com Reversed-Z* e física 3D real integrada via **Jolt Physics**.

---

## Para quem é?
- Projetos em Godot 4 que exigem **ambientes massivos e ultra-detalhados** (florestas monumentais, terrenos rochosos, construções complexas) sem sofrer com engasgos de *draw calls* da CPU.
- Desenvolvedores que precisam de malhas de altíssima densidade geométrica renderizadas sem perda visual e com transições contínuas sem *popping* abrupto de LOD.
- Projetos que necessitam de simulação física robusta via Jolt Physics sem que as trocas de LOD visual destruam ou recalculam colisores desnecessariamente.

## O que NÃO é?
- **Não** é um motor de jogo separado ou fork fechado do Godot: roda como complemento nativo (GDExtension + Compositor Effect).
- **Não** utiliza o `MultiMeshInstance3D` legado do Godot: o fluxo de rendering é 100% indireto em compute shader Vulkan RD.
- **Não** exige hardware proprietário ou extensões vendor-specific: opera em qualquer GPU compatível com Vulkan 1.2+ (Forward+), testado e validado em NVIDIA RTX.

---

## Funcionalidades Principais

1. **Baker C++ com Meshoptimizer:**
   - Utilitário CLI nativo de alta velocidade (`arboria_baker_cli.exe` / `vg_baker_cli.exe`).
   - Converte arquivos standard `.obj` em `.vgmesh` binário otimizado.
   - Particiona malhas em clusters geométricos (~128 triângulos) com hierarquia DAG monotônica, esferas de bounding e cones de normais.
2. **GPU Scene Global & Submissão $O(1)$:**
   - Agrupamento global de instâncias em GPU Storage Buffers unificados.
   - 1 Compute Dispatch de Frustum + Occlusion Culling e 1 Draw Indireto Raster Global para todo o mundo.
3. **Hi-Z Occlusion Culling em Hardware:**
   - Pirâmide hierárquica de profundidade conservadora com *Reversed-Z*.
   - Clusters e instâncias ocluídos por terreno ou objetos próximos são descartados na GPU antes do rasterizador.
4. **Integração Jolt Physics 3D Real:**
   - Suporte a `StaticBody3D` (côncavo trimesh do LOD 0, convexo ou caixa), `RigidBody3D` e `CharacterBody3D`.
   - **Cache Global de Formas Físicas:** Instâncias compartilhadas utilizam o mesmo ponteiro de `Shape3D` na memória do Jolt.
   - **Persistência Estrita:** Mudanças dinâmicas de LOD visual da câmera nunca destroem, recriam ou deslocam colisores.
   - **Dirty Caching de Repouso:** Corpos dinâmicos em repouso (`sleeping`) não emitem atualizações desnecessárias para a GPU Scene.
5. **Materiais PBR Completos:**
   - Cook-Torrance GGX, difusa Lambertiana com conservação de energia, albedo, normal mapping, roughness, metallic, emissão e alpha cutout.

---

## Instalação Rápida (5 Minutos)

### 1. Copiar o complemento para o seu projeto
Copie a pasta `addons/arboria` para o diretório raiz do seu projeto Godot:
```text
seu_projeto/
├── addons/
│   └── arboria/
│       ├── plugin.cfg
│       ├── arboria_native.gdextension
│       ├── bin/
│       └── scripts/
```
Ou execute o instalador automatizado no Windows:
```cmd
install_addon.bat "C:\Caminho\Para\SeuProjeto"
```

### 2. Ativar no Godot
1. Abra o seu projeto no **Godot 4.7+**.
2. Vá em **Project -> Project Settings -> Plugins** e ative o plugin **Arboria Virtual Geometry**.
3. Em **Project Settings -> Rendering -> Renderer**, certifique-se de que o modo selecionado é **Forward+** (`forward_plus`).
4. (Recomendado) Em **Project Settings -> Physics -> 3D**, selecione **Jolt Physics** para usufruir da simulação física de alto desempenho.

### 3. Utilização na Cena
1. No seu `WorldEnvironment`, adicione o efeito de compositor:
   ```gdscript
   ArboriaCompositorEffect.attach_to_environment($WorldEnvironment)
   ```
2. Adicione nós `ArboriaInstance3D` na árvore da cena e defina a propriedade `mesh_path` apontando para o seu arquivo `.vgmesh` gerado pelo Baker.
3. Configure `collision_mode` como desejar (`Static Concave`, `Static Convex`, `Rigid Convex`, etc.).

---

## Como Gerar Malhas (.obj -> .vgmesh)

Utilize o Baker C++ incluído na pasta `baker/`:
```bash
# Compilar o baker (Windows / Linux)
cd baker
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release

# Converter um modelo OBJ
./build/arboria_baker_cli minha_rocha.obj minha_rocha.vgmesh --verify
```

---

## Requisitos do Sistema

- **Engine:** Godot Engine 4.7+ (Forward+ / Vulkan 1.4).
- **GPU:** Placa de vídeo dedicada compatível com Vulkan 1.2+ e Subgroup Operations (NVIDIA GeForce GTX 1060 / RTX 2060+, AMD Radeon RX 5000+, Intel Arc).
- **Sistema Operacional:** Windows 10/11 (64-bit) ou Linux (x86_64).
- **Para Compilar do Código-Fonte:** CMake 3.20+, compilador C++17 (MSVC v143+ ou Clang 15+ / GCC 11+).

---

## Limitações Conhecidas

- **Objetos Deformáveis/Skinned:** O ARBORIA foi concebido para geometria estática ou instanciada rígida (rochas, vegetação densa, arquitetura, detritos). Suporte a rigs esqueléticos (skinning em GPU) está planejado para versões futuras.
- **Modos de Renderização Compatíveis:** O pipeline requer o renderizador **Forward+** do Godot. Não há suporte aos modos Mobile ou Compatibility devido à necessidade de Compute Shaders e Indirect Draw do Vulkan RD.

---

## Licença

Este projeto é disponibilizado sob a licença [MIT](LICENSE).  
Componentes de terceiros e agradecimentos encontram-se documentados em [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
