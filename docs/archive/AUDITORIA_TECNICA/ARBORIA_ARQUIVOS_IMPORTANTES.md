# Arquivos essenciais e responsabilidades

| Caminho | Função |
|---|---|
| `tools/baker/src/vg_baker_main.cpp` | OBJ, meshoptimizer, meshlets, DAG, ARBORIA2 |
| `tools/baker/CMakeLists.txt` | build do Baker |
| `tests/test_suite.py` | testes automatizados de integridade |
| `tests/small_mesh.vgmesh` | fixture binária pequena |
| `project/scripts/vgmesh_loader.gd` | leitura binária no Godot |
| `project/scripts/vg_gpu_pipeline.gd` | RenderingDevice, buffers, dispatch, indirect, fallback |
| `project/shaders/cull_clusters.glsl` | culling e contador GPU |
| `project/shaders/vg_cluster_render.gdshader` | shader de renderização |
| `project/scripts/main_viewer.gd` | integração na cena |
| `project/scripts/benchmark_fase3.gd` | instrumentação histórica |
| `project/project.godot` | configuração Forward+ |
| `project/scenes/main_viewer.tscn` | demonstração |
| `ARBORIA_MANAGER/03_GODOT_CORE_MODULE/*` | esqueleto de integração nativa, fora do workspace oficial |

O ZIP preserva caminhos relativos sob `ARBORIA_ENGINE_OFFICIAL/` e `ARBORIA_MANAGER/`. Dependências meshoptimizer e builds grandes foram omitidos; recuperar dependências pelo repositório original. Arquivos em `AUDITORIA_FASE3_FINAL` são evidências históricas, não testes desta sessão.
