# ARBORIA ENGINE — Asset Provenance & Licensing

All 3D assets included in this directory (`assets/`) are strictly open-source, procedural, or public domain (CC0 1.0 Universal). No copyrighted third-party assets without explicit permissive licensing are distributed with this repository.

---

## 1. Asset Inventory & Provenance

| Asset Name | Format | Triangle Count | Source / Generator | License |
| :--- | :---: | :---: | :--- | :---: |
| `dense_rock_test.obj` / `dense_rock.vgmesh` | Wavefront OBJ / VGMesh | 15,800 tris | Procedural noise displacement generated via `tools/generate_procedural_mesh.py` | **CC0 1.0 Universal** (Public Domain) |
| `pine_trunk_complex.obj` / `pine_trunk_complex.vgmesh` | Wavefront OBJ / VGMesh | 86,000 tris | Procedural cylindrical bark displacement tree generator | **CC0 1.0 Universal** (Public Domain) |
| `boulder_granite.obj` / `boulder_granite.vgmesh` | Wavefront OBJ / VGMesh | 2,800 tris | Procedural Voronoi noise boulder generator | **CC0 1.0 Universal** (Public Domain) |
| `rock_cluster.obj` | Wavefront OBJ | 3,120 tris | Procedural multi-rock cluster generator | **CC0 1.0 Universal** (Public Domain) |
| `small_mesh_test.obj` / `small_mesh.vgmesh` | Wavefront OBJ / VGMesh | 288 tris | Procedural subdivided cube for fast unit tests | **CC0 1.0 Universal** (Public Domain) |

---

## 2. Standardized High-Fidelity Reference Test Scenes

For benchmark parity, physical rendering tests, and stress evaluation, ARBORIA utilizes standardized research datasets provided by Intel Graphics Research. **These large files (~4 GB each) are NOT committed to the git repository**; download them directly from the official mirrors below:

### 1. Jungle Ruins Scene (4.0 GB)
- **Description:** Large-scale, photorealistic environment inspired by the Amazon Rainforest with over one trillion aggregate instanced triangle count optimized for physically based rendering (PBR). Includes Blender source and Universal Scene Description (USD) formats.
- **Official Download:** [Intel Jungle Ruins Scene (Direct Download)](https://cdrdv2.intel.com/v1/dl/getContent/844047?_gl=1*1hq1nhx*_ga*MTY2MDIyNDA5My4xNzkyNzAwNzA5*_ga_4M6YGBBVT0*czE3OTMwMjU0NjYkbzIkZzAkdDE3OTMwMjU0NjYkajYwJGwwJGgw) (4.0 GB)

### 2. Sponza Base Scene (3.71 GB)
- **Description:** Remade for modern PBR pipelines with photogrammetry-derived high-resolution geometry and 4K textures. Provides ideal images for reproducibility and research. Includes 3ds Max 2022 source, USD, glTF, and FBX.
- **Official Download:** [Intel Sponza Base Scene (Direct Download)](https://cdrdv2.intel.com/v1/dl/getContent/830833?_gl=1*1hq1nhx*_ga*MTY2MDIyNDA5My4xNzkyNzAwNzA5*_ga_4M6YGBBVT0*czE3OTMwMjU0NjYkbzIkZzAkdDE3OTMwMjU0NjYkajYwJGwwJGgw) (3.71 GB)

---

## 3. CC0 1.0 Universal License Summary

To the extent possible under law, the authors have dedicated all copyright and related and neighboring rights to the procedural geometries in this folder to the public domain worldwide under the **Creative Commons CC0 1.0 Universal (CC0 1.0) Public Domain Dedication**.
