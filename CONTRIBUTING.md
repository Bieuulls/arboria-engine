# Contribuindo com o ARBORIA ENGINE

Agradecemos o seu interesse em contribuir com o **ARBORIA ENGINE**! Este projeto é construído em código aberto para levar geometria virtualizada de ponta à comunidade Godot.

---

## 1. Como Configurar o Ambiente de Desenvolvimento

1. **Clone o repositório:**
   ```bash
   git clone https://github.com/seu-usuario/arboria-engine.git
   cd arboria-engine
   ```
2. **Compile a biblioteca C++ nativa (GDExtension):**
   ```powershell
   # Windows (PowerShell)
   .\tools\gates\build_native.ps1
   ```
   Isso compilará `libarboria_native.dll` e a copiará automaticamente para `project/bin/`.
3. **Compile o Baker CLI:**
   ```bash
   cd baker
   cmake -B build -DCMAKE_BUILD_TYPE=Release
   cmake --build build --config Release
   ```
4. **Abra o projeto de teste:**
   Abra a pasta `project/` com o **Godot 4.7.2 Forward+**.

---

## 2. Padrões de Código

- **C++:**
  - Padrão **C++17**.
  - Evite dependências externas pesadas além das já incluídas em `thirdparty/`.
  - Gerenciamento rigoroso de memória: sem vazamentos de memória ou RIDs GPU. Toda alocação deve ter destruição garantida no ciclo de vida.
- **GDScript:**
  - Tipagem estática rigorosa em todas as funções e variáveis públicas.
  - Siga a [Folha de Estilo Oficial do Godot](https://docs.godotengine.org/pt-br/4.x/tutorials/scripting/gdscript/gdscript_styleguide.html).
- **Shaders GLSL:**
  - Compatibilidade com Vulkan 1.2+ e Forward+ (`RenderingDevice`).
  - Código limpo e autodocumentado com clareza em binding indices de Uniform Sets.

---

## 3. Fluxo de Trabalho e Pull Requests

1. Crie uma branch para a sua funcionalidade ou correção:
   ```bash
   git checkout -b feature/minha-melhoria
   ```
2. Execute a suíte de testes antes de abrir o Pull Request:
   ```bash
   python tests/test_suite.py
   ```
3. Garanta que todas as cenas de teste fechem com código de saída 0 e sem vazamentos de RIDs.
4. Abra o Pull Request descrevendo claramente:
   - Qual problema está sendo resolvido.
   - Como testar e reproduzir o comportamento.
   - Evidências de desempenho ou capturas de tela, quando aplicável.
