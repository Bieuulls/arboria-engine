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

## 2. Policy on External Assets (e.g., Sponza)

- High-resolution external test scenes (such as Intel Sponza or New Sponza Curtains) are **NOT bundled** in this repository to prevent license ambiguity and large repository bloat.
- If external datasets are used for local testing, they must be converted using `tools/gltf_to_obj.py` and baked locally using `tools/baker/` without committing proprietary binaries to git.

---

## 3. CC0 1.0 Universal License Summary

To the extent possible under law, the authors have dedicated all copyright and related and neighboring rights to the procedural geometries in this folder to the public domain worldwide under the **Creative Commons CC0 1.0 Universal (CC0 1.0) Public Domain Dedication**.
