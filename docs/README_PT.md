# ARBORIA ENGINE — Geometria Virtualizada para Godot 4 (Forward+ / Vulkan 1.4)
*(Versão em Português / Portuguese Version — For English, see [README.md](../README.md))*

[![Godot Engine](https://img.shields.io/badge/Godot-4.7%2B-blue.svg)](https://godotengine.org/)
[![Vulkan](https://img.shields.io/badge/Graphics-Vulkan%201.4%20Forward%2B-red.svg)](https://www.vulkan.org/)
[![Physics](https://img.shields.io/badge/Physics-Jolt%20Physics%203D-orange.svg)](https://github.com/godot-jolt/godot-jolt)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](../LICENSE)

**ARBORIA ENGINE** é um complemento de geometria virtualizada (*Cluster-based Continuous Level of Detail / Nanite-like DAG*) para **Godot 4.7+ Forward+**.

Ele permite instanciar e renderizar cenários densos contendo dezenas de milhões de triângulos com **submissão GPU constante $O(1)$** (1 Compute Dispatch e 1 Draw Indireto global para o conjunto de instâncias), *Hierarchical Z-Buffer (Hi-Z) Occlusion Culling* em hardware, *Depth Prepass com Reversed-Z*, projeção de sombras dinâmicas via proxy e física 3D real integrada via **Jolt Physics**.

---

## Para quem é?
- Projetos em Godot 4 que exploram renderização de geometria virtualizada baseada em clusters Nanite-like DAG com seleção por erro projetado de tela.
- Desenvolvedores que precisam de malhas densas sem sobrecarregar o rasterizador de triângulos sub-pixel.
- Projetos que necessitam de simulação física robusta via Jolt Physics sem que as trocas de LOD visual afetem colisores físicos.

## O que NÃO é?
- **Não** é um fork fechado ou motor independente: opera como addon nativo (GDExtension + Compositor Effect).
- **Não** é uma bala de prata de desempenho em qualquer cenário: em cenas com contagem moderada de instâncias, o renderizador nativo do Godot é altamente eficiente e o overhead de submissão do pipeline customizado pode anular os ganhos de rasterização de clusters da GPU.
- **Não** substitui a totalidade do pipeline nativo do Godot: focado em malhas estáticas ou instanciadas rígidas.

---

## Funcionalidades Principais

1. **Baker C++ com Meshoptimizer:**
   - Utilitário CLI nativo (`arboria_baker_cli.exe`).
   - Converte malhas `.obj` em `.vgmesh` binário particionado em clusters de 128 triângulos com hierarquia DAG monotônica.
2. **GPU Scene Global & Submissão $O(1)$:**
   - Agrupamento global de instâncias em GPU Storage Buffers unificados.
   - 1 Compute Dispatch de Frustum + Occlusion Culling e 1 Draw Indireto Raster Global.
3. **Hi-Z Occlusion Culling em Hardware:**
   - Pirâmide hierárquica de profundidade conservadora com *Reversed-Z*.
4. **Projeção de Sombras Dinâmicas:**
   - Suporte nativo à projeção de sombras em luzes direcionais (`DirectionalLight3D`) via proxy interno `SHADOWS_ONLY` integrado ao Shadow Atlas e CSM do Godot Forward+.
5. **Compatibilidade PBR com StandardMaterial3D:**
   - Suporte a `material_override: StandardMaterial3D` em nós `ArboriaInstance3D` com sincronização automática de cores, texturas (Albedo, Normal Map, Roughness, Metallic) e parâmetros PBR.
6. **Integração Jolt Physics 3D Real:**
   - Suporte a colisões estáticas (`ArboriaStaticBody3D`) e dinâmicas (`ArboriaRigidBody3D`) com persistência estrita independente do nível de LOD visual.

---

## Resultados Oficiais do Benchmark e Decisão Técnica

O ARBORIA Engine é validado sob uma suíte de benchmark reproduzível de 1.000 frames por cenário, medindo tempos reais de main thread, CPU Render e GPU Render via Vulkan timestamps na GPU física (NVIDIA GeForce RTX 3050 6GB):

### Resultados Medidos (dense_rock, Resolução 1920x1080 Forward+):
| Cenário | Instâncias | Variante | Frame Time p95 (ms) | CPU Render p95 (ms) | GPU Render p95 (ms) | VRAM Média (MB) | Draws | Tris Renderizados |
| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| dense_rock | 1 | MeshInstance3D | 1.24 | 0.19 | 0.26 | 111.7 | 1 | 15.800 |
| dense_rock | 1 | MultiMeshInstance3D | 1.67 | 0.11 | 0.26 | 111.7 | 1 | 15.800 |
| dense_rock | 1 | **ARBORIA (DAG)** | **1.15** | 0.31 | 0.26 | 130.2 | 1 (indireto) | 3.866 |
| dense_rock | 500 | MeshInstance3D | 6.69 | 0.24 | 6.09 | 111.7 | 3 | 7.900.000 |
| dense_rock | 500 | MultiMeshInstance3D | 7.24 | 0.27 | 6.36 | 111.7 | 1 | 7.900.000 |
| dense_rock | 500 | **ARBORIA (DAG)** | **8.06** | 7.01 | **0.63** | 131.1 | 1 (indireto) | 337.374 |

### Parecer Técnico Honesto: `NO-GO (Sem Vantagem Mensurável)`
- **Vantagem de GPU Comprovada:** O pipeline do ARBORIA reduz drasticamente o trabalho de GPU em cenas densas (0.63 ms vs 6.09 ms do Godot em 500 instâncias — **redução de ~9.6x no tempo de GPU** e redução de 7.900.000 para 337.374 triângulos rasterizados).
- **Gargalo de CPU Identificado:** Em Godot GDScript/RenderingDevice, o overhead de submissão de CPU para atualizar buffers de instâncias (7.01 ms CPU) supera a economia de GPU, resultando em tempo de frame ligeiramente superior (8.06 ms vs 6.69 ms).
- **Decisão:** Por não atender ao critério estrito de frame time $\le 67\%$ em múltiplas combinações, o projeto registrou decisão formal de **NO-GO** para substituição automática do renderizador nativo.

---

## Validação e CI Local Unificado

O repositório inclui suíte completa de testes e validação contínua local em um único comando:

```cmd
# Executa as 5 etapas da CI Local:
ci_local.bat
```

Etapas verificadas automaticamente:
1. **Compilação C++:** Build incremental do backend nativo (`native/renderer/build`).
2. **Testes CTest:** Execução dos testes unitários C++ do renderizador nativo.
3. **Painel de Testes (27 testes):** Execução da suíte completa de testes Godot e Python (`tests/panel/panel.py --cli`).
4. **Benchmark Rápido:** Execução determinística e gravação de telemetria em `bench/results/raw.csv` e `summary.md`.
5. **Verificação de Regressão:** Neutralização completa de caminhos absolutos locais de desenvolvimento (0 ocorrências em todo o código rastreado).

---

## Instalação Rápida do Addon

### 1. Copiar o plugin para o seu projeto
Copie a pasta `addons/arboria` para a pasta do seu projeto Godot:
```cmd
install_addon.bat "C:\Caminho\Para\SeuProjeto"
```

### 2. Ativar no Godot
1. Abra o projeto no **Godot 4.7+**.
2. Vá em **Project -> Project Settings -> Plugins** e ative o plugin **Arboria Virtual Geometry**.
3. Em **Project Settings -> Rendering -> Renderer**, utilize **Forward+** (`forward_plus`).
4. (Opcional) Em **Project Settings -> Physics -> 3D**, selecione **Jolt Physics**.

---

## Compilação do Código-Fonte

```cmd
# Windows (MSVC 2022 + CMake + Ninja)
build.bat

# Linux
./build.sh
```

---

## Requisitos do Sistema

- **Motor:** Godot Engine 4.7+ (Forward+ / Vulkan 1.4).
- **GPU:** GPU dedicada compatível com Vulkan 1.2+ e Subgroup Operations (NVIDIA RTX / GTX 1060+, AMD Radeon RX 5000+, Intel Arc).
- **Sistema Operacional:** Windows 10/11 (64-bit) ou Linux (x86_64).
- **Compilador:** CMake 3.20+, MSVC v143+ (Visual Studio 2022) ou GCC 11+ / Clang 15+.

---

## Licença

Este projeto é disponibilizado sob a licença [MIT](../LICENSE).  
Componentes de terceiros e agradecimentos encontram-se documentados em [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
