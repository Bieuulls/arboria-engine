# ARBORIA ENGINE — Laboratório Profissional de Validação Gráfica (Validation Lab)

Ambiente completo de engenharia e certificação gráfica para o motor de geometria virtualizada **ARBORIA** em **Godot 4.7.2 Forward+ Vulkan** e GPU **NVIDIA GeForce RTX 3050**.

---

## 1. As 6 Ferramentas de Engenharia Obrigatórias

| Ferramenta | Finalidade Técnica | Status no PC | Link de Instalação |
| :--- | :--- | :---: | :--- |
| **Godot Engine 4.7.2** | Motor 3D de referência e execução | Instalado via WinGet | [Godot Archive](https://godotengine.org/download/archive/4.7.2-stable/) |
| **Python 3.12 + C++** | Orquestração de automação e compilação nativa | Instalado | [Python.org](https://www.python.org/downloads/) |
| **CMake 3.20+ / CTest** | Build determinístico do Baker e do Núcleo Nativo | Instalado | [CMake.org](https://cmake.org/download/) |
| **Vulkan SDK (LunarG)** | Validation Layers, sincronização GPU e SPIR-V | **Baixar** | [LunarG Vulkan SDK](https://vulkan.lunarg.com/sdk/home) |
| **RenderDoc** | Inspecionar draw calls, buffers GPU, VRAM e depth | **Baixar** | [RenderDoc Oficial](https://renderdoc.org/) |
| **NVIDIA Nsight (Graphics/Systems)** | Profiling de GPU e identificação de esperas de CPU | **Baixar** | [NVIDIA Developer](https://developer.nvidia.com/nsight-graphics) |

---

## 2. As 6 Cenas de Teste do Laboratório (Matriz de Stress)

- **LAB 01 — Geometria Extrema:** Malhas de 100k, 1M até 10M+ de triângulos para testar saturação de clusters, precisão e reconstrução lossless.
- **LAB 02 — DAG e LOD Contínuo:** Verificação de corte DAG de clusters com cores visuais por nível para detectar fendas, costuras e rachaduras.
- **LAB 03 — Hi-Z e Visibilidade (Oclusão):** Paredes oclusivas escondendo 1.000+ rochas para certificar que triângulos ocultos são 100% descartados no compute shader.
- **LAB 04 — Materiais e Iluminação PBR:** Comparativo Cook-Torrance GGX contra StandardMaterial3D do Godot com inspeção visual.
- **LAB 05 — Milhares de Instâncias:** Teste em lote com 100, 1.000, 2.000 e 10.000 instâncias para medir tempo de submissão na CPU e draw indirect.
- **LAB 06 — Streaming e Memória (VRAM):** Orçamento estrito de VRAM forçado a 2 MB com 80+ instâncias, testando eviction LRU e paginação sem vazamentos.

---

## 3. Os 5 Níveis de Certificação Interna

| Nível | Título | Critério de Aprovação |
| :---: | :--- | :--- |
| **L1** | **Funcional** | Compila limpo, abre em Vulkan Forward+ e renderiza geometria correta. |
| **L2** | **Correto** | DAG contínuo, sem fendas visuais, transformações espelhadas válidas e oclusão Hi-Z funcional. |
| **L3** | **Estável** | Zero crashes, zero vazamentos de memória e sem erros reportados por Validation Layers. |
| **L4** | **Otimizado** | Submissão de comandos rápida na CPU e frame time inferior ao melhor método convencional em grande escala. |
| **L5** | **Pronto para Distribuição** | 100% dos testes reproduzíveis via scripts automatizados sem intervenção manual. |

---

## 4. Como Executar o Diagnóstico do Ambiente

Abra o PowerShell na raiz e execute:
```powershell
powershell -NoProfile -File tools/validation_lab/scripts/check_environment.ps1
```

Para auditar os contadores do benchmark:
```powershell
python tools/validation_lab/scripts/check_benchmark.py bench/results/raw.csv
```
