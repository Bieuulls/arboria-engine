# Contributing to ARBORIA ENGINE

Thank you for your interest in contributing to **ARBORIA ENGINE**! This project is an open-source research initiative exploring GPU-driven virtualized geometry for the Godot ecosystem.

*(Para a versão em Português deste guia, consulte [docs/CONTRIBUTING_PT.md](docs/CONTRIBUTING_PT.md))*

---

## 1. Clean Clone Initialization & Build Order

In a clean checkout of the repository, baked binary files (`.vgmesh`) and editor caches (`.godot/`) are omitted to keep the repository lightweight. To initialize the environment:

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Bieuulls/arboria-engine.git
   cd arboria-engine
   ```

2. **Run the automated build script:**
   ```cmd
   # Windows
   build.bat

   # Linux
   ./build.sh
   ```

   This script executes deterministically:
   - **Step 1:** Compiles the C++ Baker CLI (`baker/build/arboria_baker_cli.exe`).
   - **Step 2:** Converts canonical `.obj` reference meshes in `assets/` into binary `.vgmesh` files and mirrors them to `project/assets/`.
   - **Step 3:** Compiles the native Forward+ C++ GDExtension library (`project/bin/libarboria_native.dll` or `.so`).
   - **Step 4:** Executes CTest native unit tests.
   - **Step 5:** Performs a headless index pass with Godot (`godot --headless --editor --quit --path project`) to generate `.godot/global_script_class_cache.cfg`.

3. **Validate LOD0 Parity:**
   ```bash
   python tests/test_lod0_parity.py
   ```

4. **Run the Full Test Suite:**
   ```bash
   python tests/panel/panel.py --cli
   ```

---

## 2. Coding Standards

- **C++:**
  - Modern **C++17** standard.
  - Minimal third-party dependencies beyond those vendorized in `thirdparty/`.
  - Strict resource management: no memory leaks or dangling GPU `RID` handles. All allocations must have lifetime guarantees.
- **GDScript:**
  - Strict static typing on all functions, parameters, and public properties.
  - Adhere to the [Godot Official GDScript Style Guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html).
- **GLSL Shaders:**
  - Compatible with Vulkan 1.2+ Forward+ (`RenderingDevice`).
  - Clear, self-documenting uniform set binding indexes and push constant structures.

---

## 3. Workflow & Pull Requests

1. **Check the Task Board:**
   Review open issues and the [CONTRIBUTOR_TASKS.md](CONTRIBUTOR_TASKS.md) board before starting work to avoid duplicating effort.

2. **Create a Topic Branch:**
   ```bash
   git checkout -b feature/your-improvement-name
   ```

3. **Verify Locally with Unified CI:**
   Before submitting your PR, ensure all 5 stages of the local CI pass:
   ```cmd
   ci_local.bat
   ```
   *(Or `.\ci_local.ps1` in PowerShell).*

4. **Submit a Pull Request:**
   Provide a clear description:
   - What problem is solved or what feature is introduced.
   - How to test and reproduce the change.
   - Profiling traces, GPU timestamps, or screenshots for any graphics/performance changes.

---

## 4. Communication & Questions

- For general discussions and technical questions, open a thread in [GitHub Discussions](https://github.com/Bieuulls/arboria-engine/discussions).
- For defects and reproducible issues, submit a [Bug Report](https://github.com/Bieuulls/arboria-engine/issues/new/choose).
- Please adhere to our [Code of Conduct](CODE_OF_CONDUCT.md) in all community interactions.
