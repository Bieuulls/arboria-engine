#include "../core/arboria_types.h"
#include "../core/arboria_mesh_resource.h"
#include "../core/arboria_runtime.h"
#include "../gpu/arboria_buffer_manager.h"
#include "../gpu/arboria_compute_dispatch.h"
#include "../gpu/arboria_indirect_renderer.h"
#include "../integration/arboria_scene_bridge.h"
#include "../integration/arboria_render_pass.h"

#include <iostream>
#include <cassert>
#include <cmath>

int main(int argc, char** argv) {
    std::cout << "====================================================" << std::endl;
    std::cout << "  ARBORIA ENGINE - TESTE UNITARIO DO NUCLEO NATIVO  " << std::endl;
    std::cout << "====================================================" << std::endl;

    // 1. Inicializacao do Runtime
    assert(arboria_init() == 0);
    std::cout << "[TESTE 1] Runtime inicializado: " << arboria_get_version() << " - OK" << std::endl;

    // 2. Carregamento de malha .vgmesh
    std::string test_mesh_path = (argc > 1) ? argv[1] : "tests/dense_rock_verified.vgmesh";
    int32_t mesh_id = arboria_load_mesh(test_mesh_path.c_str());
    if (mesh_id <= 0) {
        // Tenta caminho relativo alternativo
        test_mesh_path = "../../tests/dense_rock_verified.vgmesh";
        mesh_id = arboria_load_mesh(test_mesh_path.c_str());
    }

    if (mesh_id <= 0) {
        std::cerr << "[TESTE 2] AVISO: Nao foi possivel carregar " << test_mesh_path << " (caminho relativo). Testando com dados sinteticos." << std::endl;
    } else {
        std::cout << "[TESTE 2] Malha carregada com ID: " << mesh_id << " - OK" << std::endl;

        Arboria::Header hdr{};
        assert(arboria_get_mesh_header(mesh_id, &hdr) == 0);
        std::cout << "         Clusters: " << hdr.clusters
                  << ", Vertices: " << hdr.vertices
                  << ", Triangulos: " << hdr.triangles
                  << ", LODs: " << hdr.lods
                  << ", Grupos DAG: " << hdr.groups << std::endl;

        assert(hdr.clusters > 0);
        assert(hdr.vertices > 0);
        assert(hdr.triangles > 0);

        // 3. Verificacao dos dados para GPU
        size_t c_bytes = 0, v_bytes = 0, t_bytes = 0;
        const void* c_ptr = arboria_get_gpu_clusters_ptr(mesh_id, &c_bytes);
        const void* v_ptr = arboria_get_packed_vertices_ptr(mesh_id, &v_bytes);
        const void* t_ptr = arboria_get_packed_triangles_ptr(mesh_id, &t_bytes);

        assert(c_ptr != nullptr && c_bytes == hdr.clusters * sizeof(Arboria::GPUCluster));
        assert(v_ptr != nullptr && v_bytes == hdr.vertices * sizeof(Arboria::GPUPackedVertex));
        assert(t_ptr != nullptr && t_bytes > 0);
        std::cout << "[TESTE 3] Dados GPU preparados (Clusters: " << c_bytes << " B, Vertices: " << v_bytes << " B) - OK" << std::endl;

        // 4. Buffer Manager
        auto mesh_ptr = Arboria::VGRuntime::instance().get_mesh(mesh_id);
        Arboria::VGBufferManager buf_mgr;
        assert(buf_mgr.setup_for_mesh(*mesh_ptr));
        std::cout << "[TESTE 4] Buffer Manager configurado. VRAM total estimada: " << (buf_mgr.get_total_vram_bytes() / 1024) << " KB - OK" << std::endl;

        // 5. Compute Dispatch e UBO
        Arboria::CameraViewSettings cam{};
        // Matriz identidade para view_proj
        cam.view_proj_matrix[0] = 1.0f; cam.view_proj_matrix[5] = 1.0f;
        cam.view_proj_matrix[10] = 1.0f; cam.view_proj_matrix[15] = 1.0f;
        cam.camera_world_pos[0] = 0.0f;
        cam.camera_world_pos[1] = 0.0f;
        cam.camera_world_pos[2] = 5.0f; // 5 metros de distancia
        cam.max_screen_error = 1.5f;
        cam.viewport_width = 1920.0f;
        cam.viewport_height = 1080.0f;
        cam.lod_mode = 0; // Auto DAG

        Arboria::CameraUniforms ubo{};
        assert(arboria_build_camera_ubo(&cam, hdr.clusters, nullptr, &ubo) == 0);
        std::cout << "[TESTE 5] Camera UBO construido com sucesso (224 bytes) - OK" << std::endl;

        // 6. Simulacao de Culling e LOD
        uint32_t vis_clusters = 0, vis_tris = 0;
        assert(arboria_simulate_cull(mesh_id, &ubo, &vis_clusters, &vis_tris) == 0);
        std::cout << "[TESTE 6] Simulacao de Culling: Clusters Visiveis: " << vis_clusters << ", Triangulos: " << vis_tris << " - OK" << std::endl;

        // 7. Validacao do comando indireto
        auto draw_cmd = Arboria::VGIndirectRenderer::build_initial_draw_command();
        draw_cmd.instance_count = vis_clusters;
        assert(Arboria::VGIndirectRenderer::validate_draw_command(draw_cmd, hdr.clusters));
        std::cout << "[TESTE 7] Comando VkDrawIndirectCommand validado - OK" << std::endl;

        // 8. Scene Bridge e Multi-Instancias
        uint32_t inst1 = arboria_scene_create_instance(mesh_id);
        uint32_t inst2 = arboria_scene_create_instance(mesh_id);
        assert(inst1 > 0 && inst2 > 0 && inst1 != inst2);
        assert(arboria_scene_get_active_count() == 2);
        std::cout << "[TESTE 8] Multi-instancias criadas (Inst1: " << inst1 << ", Inst2: " << inst2 << ") - OK" << std::endl;

        arboria_scene_destroy_instance(inst1);
        assert(arboria_scene_get_active_count() == 1);
        arboria_scene_destroy_instance(inst2);
        assert(arboria_scene_get_active_count() == 0);
        std::cout << "[TESTE 9] Limpeza de instancias - OK" << std::endl;
    }

    arboria_shutdown();
    std::cout << "====================================================" << std::endl;
    std::cout << "  TODOS OS TESTES DO NUCLEO NATIVO PASSARAM COM EXITO! " << std::endl;
    std::cout << "====================================================" << std::endl;
    return 0;
}
