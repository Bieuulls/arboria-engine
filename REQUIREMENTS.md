# ARBORIA ENGINE — Requisitos de Sistema e Dependências

Este documento detalha todos os pré-requisitos, versões recomendadas e dependências necessárias para executar, integrar ou compilar o **ARBORIA ENGINE**.

---

## 1. Requisitos de Execução (Runtime do Usuário)

Para utilizar o complemento em projetos Godot:

- **Engine:** [Godot Engine v4.7.2 Stable](https://godotengine.org/) (ou superior da linha 4.x).
  - **Renderer Obrigatório:** Forward+ (`forward_plus`). O pipeline utiliza `RenderingDevice`, Compute Shaders, SSBOs e Indirect Draw do Vulkan 1.4. Não funciona nos modos Mobile ou Compatibility.
- **Backend Físico Recomendado:** **Jolt Physics 3D** (integrado no Godot 4.7+ ou via extensão oficial).
- **GPU (Hardware Gráfico):**
  - Compatibilidade com Vulkan 1.2+ e extensões de Subgroup Operations.
  - Testado e validado em: NVIDIA GeForce RTX 3050 (Laptop/Desktop), RTX 3060/4060+.
  - Drivers NVIDIA Game Ready / Studio 550.00+ atualizados.
- **Sistema Operacional:** Windows 10/11 64-bit ou Linux x86_64 com drivers Vulkan proprietários/Mesa atualizados.

---

## 2. Requisitos de Compilação (Build do Código Nativo)

Para compilar a biblioteca GDExtension nativa (`libarboria_native.dll` / `.so`) e o utilitário Baker CLI (`arboria_baker_cli.exe`):

### Compilador C++
- Suporte estrito a **C++17** ou superior.
- **Windows:**
  - Microsoft Visual Studio 2022 (MSVC v143+) **OU**
  - LLVM Clang 15+ / MinGW-w64 GCC 12+.
- **Linux:** GCC 11+ ou Clang 14+.

### CMake
- **Versão Mínima:** CMake 3.20 ou superior.

### Interface GDExtension
- O ARBORIA utiliza a **interface nativa C GDExtension (`gdextension_interface.h`)**, sem acoplamento rígido ao `godot-cpp`, garantindo compatibilidade binária direta e carregamento imediato pelo motor.

### Dependências de Terceiros Incluídas
- **meshoptimizer** (licença MIT): Incluído diretamente na pasta `baker/thirdparty/meshoptimizer/` para simplificação geométrica e clusterização de triângulos.

---

## 3. Requisitos para Scripts de Testes e Benchmark
- **Python:** Python 3.10 ou superior.
- **Bibliotecas Python Opcionais:**
  - `Pillow` (para testes de regressão de imagem MAE).
  - Biblioteca padrão do Python (`json`, `subprocess`, `os`, `sys`, `csv`).
