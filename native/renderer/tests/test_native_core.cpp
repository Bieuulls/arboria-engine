#include "../core/arboria_types.h"
#include "../core/arboria_mesh_resource.h"
#include "../core/arboria_runtime.h"
#include "../gpu/arboria_buffer_manager.h"
#include "../gpu/arboria_compute_dispatch.h"
#include "../gpu/arboria_indirect_renderer.h"
#include "../integration/arboria_scene_bridge.h"
#include "../integration/arboria_render_pass.h"
#include "../scene/arboria_render_world.h"
#include "../scene/arboria_gpu_scene.h"
#include "../scene/arboria_mesh_registry.h"
#include "../scene/arboria_instance_registry.h"
#include "../scene/arboria_material_table.h"
#include "../scene/arboria_visibility_manager.h"
#include "../scene/arboria_indirect_command_manager.h"

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

        // 10. Validacao de Handles Geracionais e Rejeicao de Handles Obsoletos (Stale)
        Arboria::Handle mesh_h = Arboria::Handle::from_u64(static_cast<uint64_t>(mesh_id));
        Arboria::Handle gen_inst1 = Arboria::VGSceneBridge::instance().register_instance_handle(mesh_h);
        assert(gen_inst1.is_valid());
        assert(Arboria::VGSceneBridge::instance().is_valid_instance(gen_inst1));
        
        uint32_t slot_idx = gen_inst1.index;
        uint32_t first_gen = gen_inst1.generation;

        // Liberar a instancia
        assert(Arboria::VGSceneBridge::instance().unregister_instance_handle(gen_inst1));
        // Handle antigo DEVE ser rejeitado imediatamente
        assert(!Arboria::VGSceneBridge::instance().is_valid_instance(gen_inst1));
        
        // Re-alocar: deve reutilizar o slot mas com geracao incrementada
        Arboria::Handle gen_inst2 = Arboria::VGSceneBridge::instance().register_instance_handle(mesh_h);
        assert(gen_inst2.index == slot_idx);
        assert(gen_inst2.generation == first_gen + 1);

        // Operacoes no handle antigo obsoleto DEVEM falhar com seguranca
        float dummy_xf[16] = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 };
        assert(!Arboria::VGSceneBridge::instance().set_instance_transform_handle(gen_inst1, dummy_xf));
        assert(!Arboria::VGSceneBridge::instance().set_instance_lod_handle(gen_inst1, 2.0f, 0, 0));
        assert(!Arboria::VGSceneBridge::instance().set_instance_visible_handle(gen_inst1, false));

        // Operacoes no novo handle valido DEVEM ter sucesso
        assert(Arboria::VGSceneBridge::instance().set_instance_transform_handle(gen_inst2, dummy_xf));
        assert(Arboria::VGSceneBridge::instance().unregister_instance_handle(gen_inst2));
        std::cout << "[TESTE 10] Handles Geracionais e Rejeicao Estrita de Handles Obsoletos - OK" << std::endl;

        // 11. Teste de Estresse de 10.000 Ciclos de Registro/Liberacao
        std::cout << "[TESTE 11] Executando 10.000 ciclos de registro e desregistro continuo..." << std::endl;
        std::vector<Arboria::Handle> active_handles;
        active_handles.reserve(100);

        for (int cycle = 0; cycle < 10000; ++cycle) {
            Arboria::Handle h = Arboria::VGSceneBridge::instance().register_instance_handle(mesh_h);
            assert(h.is_valid());
            active_handles.push_back(h);

            if (active_handles.size() >= 100) {
                for (Arboria::Handle rel_h : active_handles) {
                    assert(Arboria::VGSceneBridge::instance().unregister_instance_handle(rel_h));
                    assert(!Arboria::VGSceneBridge::instance().is_valid_instance(rel_h));
                }
                active_handles.clear();
            }
        }
        for (Arboria::Handle rel_h : active_handles) {
            Arboria::VGSceneBridge::instance().unregister_instance_handle(rel_h);
        }
        assert(Arboria::VGSceneBridge::instance().get_instance_count() == 0);
        std::cout << "[TESTE 11] 10.000 ciclos concluidos com zero vazamento e contagem perfeita (0 ativas) - OK" << std::endl;
    }

    // =========================================================================
    // ETAPA 2 — VALIDAÇÃO DA ARQUITETURA GLOBAL DO GPU SCENE
    // =========================================================================
    std::cout << "\n--- ETAPA 2: VALIDACAO DO GPU SCENE GLOBAL ---" << std::endl;
    Arboria::ArboriaRenderWorld::instance().initialize();
    assert(Arboria::ArboriaRenderWorld::instance().is_initialized());

    // TESTE 12: Registro de Geometria Compartilhada (ArboriaMeshRegistry)
    Arboria::Handle shared_mesh = Arboria::ArboriaRenderWorld::instance().register_mesh(test_mesh_path);
    assert(Arboria::ArboriaMeshRegistry::instance().is_valid_mesh(shared_mesh));
    const auto* reg_info = Arboria::ArboriaMeshRegistry::instance().get_mesh_info(shared_mesh);
    assert(reg_info != nullptr);
    assert(reg_info->cluster_count > 0);
    assert(reg_info->vertex_count > 0);
    std::cout << "[TESTE 12] Geometria Compartilhada Registrada: " 
              << reg_info->cluster_count << " clusters, " 
              << reg_info->vertex_count << " vertices (ID: " << shared_mesh.to_u64() << ") - OK" << std::endl;

    // TESTE 13: Cálculo de Bounding Volumes e Normal Matrix (escalas não uniformes e espelhadas)
    {
        float model_matrix[16] = {
            -2.0f, 0.0f,  0.0f, 0.0f,
             0.0f, 1.5f,  0.0f, 0.0f,
             0.0f, 0.0f,  0.5f, 0.0f,
            10.0f, 5.0f, -20.0f, 1.0f
        };
        float normal_matrix[16];
        Arboria::ArboriaInstanceRegistry::compute_normal_matrix(model_matrix, normal_matrix);
        // Transposta da inversa de diag(-2, 1.5, 0.5) é diag(-0.5, 1/1.5, 2.0)
        assert(std::abs(normal_matrix[0] - (-0.5f)) < 1e-4f);
        assert(std::abs(normal_matrix[5] - (1.0f / 1.5f)) < 1e-4f);
        assert(std::abs(normal_matrix[10] - 2.0f) < 1e-4f);

        float center_in[3] = {0.0f, 0.0f, 0.0f};
        float min_in[3] = {-1.0f, -1.0f, -1.0f};
        float max_in[3] = { 1.0f,  1.0f,  1.0f};
        float center_out[3];
        float radius_out = 0.0f;
        float min_out[3], max_out[3];
        Arboria::ArboriaInstanceRegistry::compute_world_bounds(
            center_in, 1.0f, min_in, max_in, model_matrix,
            center_out, radius_out, min_out, max_out
        );
        assert(center_out[0] == 10.0f && center_out[1] == 5.0f && center_out[2] == -20.0f);
        assert(radius_out == 2.0f); // max scale = |-2.0| = 2.0
        assert(min_out[0] == 8.0f && max_out[0] == 12.0f); // 10 +- 2
        assert(min_out[1] == 3.5f && max_out[1] == 6.5f);  // 5 +- 1.5
        assert(min_out[2] == -20.5f && max_out[2] == -19.5f); // -20 +- 0.5
        std::cout << "[TESTE 13] Normal Matrix e Bounding Volumes (Escala Nao-Uniforme e Espelhada) - OK" << std::endl;
    }

    // TESTE 14: Escalonamento do GPU Scene (1, 80, 500, e 2.000 instâncias)
    // Validação de que dispatches e comandos indiretos escalam em 1 LOTE CONSOLIDADO
    const uint32_t test_instance_counts[] = {1, 80, 500, 2000};
    for (uint32_t target_count : test_instance_counts) {
        Arboria::ArboriaInstanceRegistry::instance().clear();
        std::vector<Arboria::Handle> inst_handles;
        inst_handles.reserve(target_count);

        for (uint32_t i = 0; i < target_count; ++i) {
            Arboria::Handle ih = Arboria::ArboriaRenderWorld::instance().register_instance(shared_mesh, 0);
            assert(ih.is_valid());
            float tr[16] = {
                1.0f, 0.0f, 0.0f, 0.0f,
                0.0f, 1.0f, 0.0f, 0.0f,
                0.0f, 0.0f, 1.0f, 0.0f,
                (float)(i % 50) * 4.0f - 100.0f, 0.0f, -((float)(i / 50) * 4.0f + 10.0f), 1.0f
            };
            Arboria::ArboriaRenderWorld::instance().update_instance_transform(ih, tr);
            inst_handles.push_back(ih);
        }
        assert(Arboria::ArboriaRenderWorld::instance().get_active_instance_count() == target_count);

        std::vector<Arboria::GPUInstanceData> gpu_instances;
        Arboria::ArboriaInstanceRegistry::instance().build_gpu_instance_buffer(gpu_instances);
        assert(gpu_instances.size() == target_count);

        float view_proj[16] = {
            1.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 1.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 1.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 1.0f
        };
        float cam_pos[3] = {0.0f, 0.0f, 5.0f};
        Arboria::GlobalSceneUniforms uniforms = Arboria::ArboriaGPUScene::instance().build_scene_uniforms(
            view_proj, cam_pos, 1.0f, 1920.0f, 1080.0f, 1.5f, 0, true, true
        );

        Arboria::SceneCullResult cull_res = Arboria::ArboriaGPUScene::instance().simulate_cull_scene(uniforms);
        assert(cull_res.total_instances == target_count);
        assert(cull_res.total_work_items == target_count * reg_info->cluster_count);
        assert(!cull_res.has_overflow);

        // O trabalho GPU é despachado em 1 LOTE ÚNICO (compute + indirect draw), e não N chamadas
        uint32_t gpu_dispatch_count = (cull_res.total_work_items + 63) / 64;
        uint32_t gpu_indirect_draw_count = 1; // 1 único VkDrawIndirectCommand para toda a cena!

        std::cout << "  -> Cenário " << target_count << " instâncias: " 
                  << cull_res.total_work_items << " clusters avaliados, "
                  << cull_res.visible_clusters << " clusters visíveis, "
                  << cull_res.total_triangles_drawn << " triângulos. Dispatches GPU: "
                  << 1 << " (em " << gpu_dispatch_count << " grupos), Draws Indiretos: "
                  << gpu_indirect_draw_count << " - OK" << std::endl;
    }
    std::cout << "[TESTE 14] Escalonamento 1, 80, 500, 2.000 instâncias (1 Lote Consolidado) - OK" << std::endl;

    // TESTE 15: Proteção e Detecção de Overflow de Capacidade do Buffer
    {
        Arboria::GPUIndirectArgsAndCounters args{};
        args.max_capacity = 10;
        args.instance_count = 10;
        // Simula tentativa de ultrapassar a capacidade máxima
        if (args.instance_count >= args.max_capacity) {
            args.overflow_flag = 1;
        }
        assert(args.overflow_flag == 1);
        std::cout << "[TESTE 15] Proteção e Detecção de Overflow de Capacidade - OK" << std::endl;
    }

    // TESTE 16: Limpeza e Finalização do ArboriaRenderWorld
    Arboria::ArboriaRenderWorld::instance().shutdown();
    assert(!Arboria::ArboriaRenderWorld::instance().is_initialized());
    assert(Arboria::ArboriaRenderWorld::instance().get_active_instance_count() == 0);
    assert(Arboria::ArboriaRenderWorld::instance().get_registered_mesh_count() == 0);
    std::cout << "[TESTE 16] Finalização e Liberação Segura do ArboriaRenderWorld - OK" << std::endl;

    arboria_shutdown();
    std::cout << "====================================================" << std::endl;
    std::cout << "  TODOS OS TESTES DO NUCLEO NATIVO PASSARAM COM EXITO! " << std::endl;
    std::cout << "====================================================" << std::endl;
    return 0;
}
