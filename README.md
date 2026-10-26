# ARBORIA ENGINE — Virtual Geometry for Godot 4 (Forward+ / Vulkan 1.4)

[![Godot Engine](https://img.shields.io/badge/Godot-4.7%2B-blue.svg)](https://godotengine.org/)
[![Vulkan](https://img.shields.io/badge/Graphics-Vulkan%201.4%20Forward%2B-red.svg)](https://www.vulkan.org/)
[![Physics](https://img.shields.io/badge/Physics-Jolt%20Physics%203D-orange.svg)](https://github.com/godot-jolt/godot-jolt)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Roadmap](https://img.shields.io/badge/Community-Roadmap-purple.svg)](ROADMAP.md)
[![Docs (PT-BR)](https://img.shields.io/badge/Docs-Portugu%C3%AAs-informational.svg)](docs/README_PT.md)

**ARBORIA ENGINE** is an experimental GPU-driven virtualized-geometry renderer (*Cluster-based Continuous Level of Detail / Nanite-like DAG*) for **Godot 4.7+ Forward+**.

It enables instancing and rendering massive scenes containing tens of millions of triangles with **constant $O(1)$ GPU submission** (a single compute dispatch and a single global indirect raster draw for the active batch), hardware **Hierarchical Z-Buffer (Hi-Z) Occlusion Culling**, a **Reversed-Z Depth Prepass**, native dynamic shadow projection via internal proxies, and integrated 3D physical collisions powered by **Jolt Physics**.

> [!NOTE]
> **Engineering Philosophy:** No unsupported benchmark claims, no hidden tricks, and no speedup accepted at the expense of correct geometry. We publish reproducible measurements, known limitations, and active research questions.

---

## Architecture Overview

```
                      +-----------------------------+
                      |   C++ Baker CLI (Offline)   |
                      |   Meshoptimizer + DAG Gen   |
                      +--------------+--------------+
                                     | .vgmesh
                                     v
                      +-----------------------------+
                      |  Global GPU Scene Buffers   |
                      | (Clusters, Transforms, PBR) |
                      +--------------+--------------+
                                     |
                                     v
+------------------------+   Compute Dispatch    +-------------------------+
| Hi-Z Depth Mip-Pyramid | <-------------------  | GPU Frustum + Occlusion |
|     (Reversed-Z)       |                       |        Culling          |
+------------------------+                       +------------+------------+
                                                              |
                                                              v Visible Clusters
                                                 +-------------------------+
                                                 | Global Indirect Raster  |
                                                 |        Draw Call        |
                                                 +------------+------------+
                                                              |
                                                              v
                                                 +-------------------------+
                                                 | Forward+ G-Buffer / CSM |
                                                 +-------------------------+
```

### Core Subsystems

1. **Native C++ Baker with Meshoptimizer:**
   - Standalone CLI tool (`arboria_baker_cli.exe`).
   - Partitions arbitrary `.obj` triangle meshes into bounded 128-triangle clusters with a monotonic directed acyclic graph (DAG) hierarchy for seamless projected error LOD selection.
2. **GPU Scene Global & $O(1)$ Submission:**
   - Global instance aggregation inside unified GPU Storage Buffers (`RenderingDevice`).
   - 1 Compute dispatch for culling + 1 indirect draw command for the entire visible cluster stream.
3. **Hardware Hi-Z Occlusion Culling:**
   - Conservative hierarchical depth pyramid constructed from the Godot Forward+ depth texture with Reversed-Z semantics.
4. **Dynamic Shadow Projection:**
   - Directional light shadow casting (`DirectionalLight3D`) through an internal `SHADOWS_ONLY` proxy pass integrated directly into Godot's Cascaded Shadow Maps (CSM) and Shadow Atlas.
5. **Full PBR Fidelity:**
   - Automatic material binding and synchronization with Godot's `StandardMaterial3D` (Albedo, Normal maps, Roughness, Metallic, and emission).
6. **Jolt Physics 3D Integration:**
   - Static (`ArboriaStaticBody3D`) and dynamic (`ArboriaRigidBody3D`) rigid body physics decoupled from visual LOD transitions to guarantee collision stability.

---

## Measured Benchmarks & Engineering Findings

ARBORIA is validated under an automated, reproducible benchmark harness running 1,000 frames per configuration, measuring physical Vulkan timestamp queries on an NVIDIA GeForce RTX 3050 6GB:

### Results: `dense_rock` Scene (1920x1080 Forward+)

| Scenario | Instances | Variant | Frame Time p95 | CPU Render p95 | GPU Render p95 | VRAM Avg | Draws | Rendered Tris |
| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| dense_rock | 1 | MeshInstance3D | 1.24 ms | 0.19 ms | 0.26 ms | 111.7 MB | 1 | 15,800 |
| dense_rock | 1 | MultiMeshInstance3D | 1.67 ms | 0.11 ms | 0.26 ms | 111.7 MB | 1 | 15,800 |
| dense_rock | 1 | **ARBORIA (DAG)** | **1.15 ms** | 0.31 ms | 0.26 ms | 130.2 MB | 1 (indirect) | **3,866** |
| dense_rock | 500 | MeshInstance3D | 6.69 ms | 0.24 ms | 6.09 ms | 111.7 MB | 3 | 7,900,000 |
| dense_rock | 500 | MultiMeshInstance3D | 7.24 ms | 0.27 ms | 6.36 ms | 111.7 MB | 1 | 7,900,000 |
| dense_rock | 500 | **ARBORIA (DAG)** | **8.06 ms** | 7.01 ms | **0.63 ms** | 131.1 MB | 1 (indirect) | **337,374** |

### Honest Technical Evaluation

- **Measured GPU Advantage:** In high-density scenes, ARBORIA drops GPU rendering time from 6.09 ms to 0.63 ms (**~9.6x GPU reduction**) by culling sub-pixel detail and rasterizing only 337,374 triangles compared to 7.9 million triangles in Godot native.
- **Identified CPU Bottleneck:** In the current GDScript/RenderingDevice binding layer, per-frame CPU submission and instance buffer updates take 7.01 ms CPU time, which exceeds the GPU savings and leads to a slightly higher total frame time (8.06 ms vs 6.69 ms).
- **Engineering Conclusion:** We documented a **NO-GO** on claiming full replacement of native meshes today. Fixing this bottleneck via persistent dirty-range instance buffers and heterogeneous batching is the #1 priority in [ROADMAP.md](ROADMAP.md) (Phase B).

---

## Quickstart & Installation

### Requirements

- **Godot Engine:** 4.7+ (Forward+ / Vulkan 1.4).
- **GPU:** Dedicated GPU with Vulkan 1.2+ and Subgroup Operations (NVIDIA RTX / GTX 1060+, AMD Radeon RX 5000+, Intel Arc).
- **Operating System:** Windows 10/11 (64-bit) or Linux (x86_64).
- **Build Tools (from source):** CMake 3.20+, MSVC 2022 (v143+) or GCC 11+ / Clang 15+.

### Using the Addon

1. Copy or install the addon into your project:
   ```cmd
   install_addon.bat "C:\Path\To\YourGodotProject"
   ```
2. In Godot, navigate to **Project -> Project Settings -> Plugins** and enable **Arboria Virtual Geometry**.
3. In **Project Settings -> Rendering -> Renderer**, ensure **Forward+** is selected.

---

## Building from Source

The repository provides automated, single-command build scripts that compile the baker, convert reference assets, build the native GDExtension library, run CTest unit tests, and warm the Godot editor cache:

```cmd
# Windows (MSVC 2022 + CMake + Ninja)
build.bat

# Linux
./build.sh
```

### Local Continuous Integration (Unified CI)

Run the 5-stage local validation suite before opening pull requests:

```cmd
ci_local.bat
```

Stages verified:
1. Native C++ backend incremental compilation.
2. CTest unit test suite.
3. 27-test Godot & Python integration suite (`tests/panel/panel.py --cli`).
4. Deterministic benchmark telemetry recording.
5. Regression & path leak auditor (0 local absolute paths permitted).

---

## Contributing & Roadmap

We are building ARBORIA in the open and welcome graphics engineers, Godot contributors, shader specialists, technical artists, and testers:

- 📋 [**Community Roadmap**](ROADMAP.md) — Strategic phases and research milestones.
- 🎯 [**Contributor Task Board**](CONTRIBUTOR_TASKS.md) — Concrete, scoped issues ready to be claimed.
- 🤝 [**Contributing Guide**](CONTRIBUTING.md) — Guidelines, code standards, and PR process.
- 🛡️ [**Code of Conduct**](CODE_OF_CONDUCT.md) & [**Security Policy**](SECURITY.md).
- 🌐 [**Landing Page (GitHub Pages)**](docs/index.html) — Visual overview of the project.

---

## License

This project is licensed under the [MIT License](LICENSE).  
Third-party libraries and notices are documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).  
3D reference asset origins and licenses are documented in [assets/README.md](assets/README.md).
