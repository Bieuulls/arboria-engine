# Contribuindo com o ARBORIA ENGINE

Agradecemos o seu interesse em contribuir com o **ARBORIA ENGINE**! Este projeto é construído em código aberto para levar geometria virtualizada de ponta à comunidade Godot.

---

## 1. Ordem de Inicialização e Build para Clones Novos

Em um clone limpo do repositório, os arquivos `.vgmesh` e o cache de scripts `.godot/` não vêm versionados. Para inicializar e validar o ambiente corretamente:

1. **Clone o repositório:**
   ```bash
   git clone https://github.com/seu-usuario/arboria-engine.git
   cd arboria-engine
   ```
2. **Execute o script de compilação e inicialização integrada:**
   ```cmd
   # Windows
   build.bat

   # Linux
   ./build.sh
   ```
   Esse script executa automaticamente em ordem determinística:
   - **Passo 1:** Compilação do Baker CLI C++ (`baker/build/arboria_baker_cli.exe`).
   - **Passo 2:** Geração automática dos arquivos binários `.vgmesh` a partir dos `.obj` de referência em `assets/` e sincronização para `project/assets/`.
   - **Passo 3:** Compilação da biblioteca nativa C++ Forward+ (`project/bin/libarboria_native.dll`).
   - **Passo 4:** Execução dos testes unitários C++ (CTest).
   - **Passo 5:** Indexação inicial do editor Godot (`godot --headless --editor --quit --path project`), gerando `.godot/global_script_class_cache.cfg` para resolução de `ArboriaMeshLoader` e classes GDExtension.

3. **Validação de Paridade Geométrica (LOD0):**
   ```bash
   python tests/test_lod0_parity.py
   ```
4. **Execução do Painel Completo de Testes:**
   ```bash
   python tests/panel/panel.py --cli
   ```

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
