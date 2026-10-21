# 🌲 Arboria Engine — Virtual Geometry Core

[![Godot Engine](https://img.shields.io/badge/Godot-4.7%2B%20Forward%2B-blue.svg)](https://godotengine.org)
[![Vulkan](https://img.shields.io/badge/Vulkan-1.3%2F1.4-red.svg)](https://www.vulkan.org)
[![C++](https://img.shields.io/badge/C%2B%2B-17-00599C.svg)](https://isocpp.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **High-Fidelity Virtualized Geometry Pipeline (Nanite-like) for Godot 4 using Vulkan Compute Shaders, DAG Cluster Hierarchy, and Hardware Vertex-Pulling.**

---

## 🌟 Overview

Arboria Engine is an open-source virtual geometry rendering architecture engineered to process and render dense 3D meshes with millions of polygons at real-time frame rates without per-frame CPU bottlenecks or memory saturation.

### Key Pillars:
1. **Zero CPU Readback per Frame:** Geometry culling, screen-error projection, and cluster selection occur 100% on the GPU via Vulkan Compute (`RenderingDevice`).
2. **DAG Cluster Hierarchy:** 3D meshes are segmented into discrete clusters (~128 triangles) organized into hierarchical Directed Acyclic Graphs with parent-child bounding spheres and projected geometric error metrics.
3. **Vertex-Pulling Spatial Rendering:** Selected clusters are streamed into VRAM buffers and fetched dynamically in a Godot `spatial` shader via `Texture2DRD (RGBA32F)` and `MultiMeshInstance3D`, avoiding dynamic mesh regeneration.
4. **Sub-millisecond Compute Overhead:** Frustum culling and LOD selection execute in **< 0.05 ms** on modern GPUs.

---

## 📂 Repository Structure

```text
arboria-engine/
├── project/                     # Official Godot 4.7+ Forward+ Project
│   ├── project.godot            # Godot configuration
│   ├── scenes/
│   │   ├── main_viewer.tscn     # Real-time GPU cluster inspection viewer
│   │   └── MainWorld.tscn       # Open-world test environment
│   ├── scripts/
│   │   ├── vg_gpu_pipeline.gd   # Vulkan RenderingDevice Compute orchestrator
│   │   ├── vgmesh_loader.gd     # Binary .vgmesh parser & GPU buffer builder
│   │   └── main_viewer.gd       # Runtime HUD, metrics & camera logic
│   ├── shaders/
│   │   ├── cull_clusters.glsl   # GPU Compute shader (Culling + LOD selection)
│   │   └── vg_cluster_render.gdshader # Vertex pulling spatial shader
│   └── assets/                  # Sample .vgmesh test assets
│
├── tools/
│   └── baker/                   # Native C++ Mesh Cluster Baker
│       ├── CMakeLists.txt       # Build system
│       ├── src/
│       │   └── vg_baker_main.cpp# Cluster partitioning, simplification & DAG builder
│       └── thirdparty/          # meshoptimizer library
│
├── tests/                       # Automated validation suite
│   └── test_suite.py            # DAG hierarchy and bounds integrity tests
│
├── docs/                        # Technical specifications & architecture blueprints
├── .gitignore                   # Godot 4 & C++ gitignore
├── LICENSE                      # MIT License
└── README.md                    # Project documentation
```

---

## 🚀 Quick Start

### 1. Requirements
* **Godot 4.3+** (Forward+ / Vulkan renderer)
* **Vulkan 1.2+** compatible GPU (NVIDIA GTX 1060 / AMD RX 580 or newer)
* **CMake 3.20+** & C++17 compiler (GCC, Clang, or MSVC) for building the baker.

### 2. Running the Viewer
1. Open Godot 4.
2. Import the `project/project.godot` file.
3. Run the project (`F5`) or load `project/scenes/main_viewer.tscn`.
4. Fly the camera using **W, A, S, D** and mouse to inspect dynamic cluster LOD transitions in real time.

### 3. Compiling the C++ Baker (Optional)
```bash
cd tools/baker
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release
```
To bake an `.obj` into `.vgmesh`:
```bash
vg_baker_cli input_mesh.obj output_mesh.vgmesh
```

---

## 🧪 Validation & Test Suite
Run the automated validation suite to verify DAG links, bounding spheres, and index buffer consistency:
```bash
python tests/test_suite.py
```

---

## 📄 License
This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.
