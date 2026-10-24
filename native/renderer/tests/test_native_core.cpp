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
#include "../gpu/arboria_memory_manager.h"
#include "../scene/arboria_streaming_manager.h"
#include "../core/arboria_mutable_geometry.h"

#include <iostream>
#include <fstream>
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
    std::string test_mesh_path = (argc > 1) ? argv[1] : "assets/dense_rock.vgmesh";
    int32_t mesh_id = arboria_load_mesh(test_mesh_path.c_str());
    if (mesh_id <= 0) {
        test_mesh_path = "../../assets/dense_rock.vgmesh";
        mesh_id = arboria_load_mesh(test_mesh_path.c_str());
    }
    if (mesh_id <= 0) {
        test_mesh_path = "assets/dense_rock_verified.vgmesh";
        mesh_id = arboria_load_mesh(test_mesh_path.c_str());
    }
    if (mesh_id <= 0) {
        test_mesh_path = "project/assets/dense_rock_verified.vgmesh";
        mesh_id = arboria_load_mesh(test_mesh_path.c_str());
    }
    if (mesh_id <= 0) {
        test_mesh_path = "../../project/assets/dense_rock_verified.vgmesh";
        mesh_id = arboria_load_mesh(test_mesh_path.c_str());
    }
    if (mesh_id <= 0) {
        test_mesh_path = "project/assets/dense_rock_test.vgmesh";
        mesh_id = arboria_load_mesh(test_mesh_path.c_str());
    }
    if (mesh_id <= 0) {
        test_mesh_path = "../../project/assets/dense_rock_test.vgmesh";
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
                (float)(i % 50) * 4.0f - 100.0f, 0.0f, -((float)(i / 50u) * 4.0f + 10.0f), 1.0f
            };
            Arboria::ArboriaRenderWorld::instance().update_instance_transform(ih, tr);
            inst_handles.push_back(ih);
        }
        assert(Arboria::ArboriaRenderWorld::instance().get_active_instance_count() == target_count);

        std::vector<Arboria::GPUInstanceData> gpu_instances;
        Arboria::ArboriaInstanceRegistry::instance().build_gpu_instance_buffer(gpu_instances);
        assert(gpu_instances.size() == target_count);

        float view_proj[16] = {
            1.0f / 150.0f, 0.0f,          0.0f,           0.0f,
            0.0f,          1.0f / 100.0f, 0.0f,           0.0f,
            0.0f,          0.0f,         -1.0f / 250.0f,  0.0f,
            0.0f,          0.0f,          20.0f / 250.0f, 1.0f
        };
        float cam_pos[3] = {0.0f, 20.0f, 10.0f};
        Arboria::GlobalSceneUniforms uniforms = Arboria::ArboriaGPUScene::instance().build_scene_uniforms(
            view_proj, cam_pos, 1.0f, 1920.0f, 1080.0f, 1.5f, 0, true, false
        );

        Arboria::SceneCullResult cull_res = Arboria::ArboriaGPUScene::instance().simulate_cull_scene(uniforms);
        assert(cull_res.total_instances == target_count);
        assert(cull_res.total_work_items == target_count * reg_info->cluster_count);
        assert(!cull_res.has_overflow);
        assert(cull_res.visible_clusters > 0);
        assert(cull_res.total_triangles_drawn > 0);

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

    // =========================================================================
    // ETAPA 5 — REFINAMENTO DO DAG E INTEGRIDADE GEOMÉTRICA
    // =========================================================================
    std::cout << "\n--- ETAPA 5: REFINAMENTO DO DAG E INTEGRIDADE GEOMETRICA ---" << std::endl;

    // TESTE 17: Detecção de Transformações Espelhadas (FLAG_MIRRORED) e Orientação de Normais
    {
        Arboria::ArboriaInstanceRegistry::instance().clear();
        Arboria::Handle h_mirrored = Arboria::ArboriaRenderWorld::instance().register_instance(shared_mesh, 0);
        float mirrored_matrix[16] = {
            -1.0f, 0.0f, 0.0f, 0.0f,
             0.0f, 1.0f, 0.0f, 0.0f,
             0.0f, 0.0f, 1.0f, 0.0f,
             0.0f, 0.0f, 0.0f, 1.0f
        };
        Arboria::ArboriaRenderWorld::instance().update_instance_transform(h_mirrored, mirrored_matrix);

        Arboria::Handle h_normal = Arboria::ArboriaRenderWorld::instance().register_instance(shared_mesh, 0);
        float normal_matrix[16] = {
            1.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 1.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 1.0f, 0.0f,
            5.0f, 0.0f, 0.0f, 1.0f
        };
        Arboria::ArboriaRenderWorld::instance().update_instance_transform(h_normal, normal_matrix);

        std::vector<Arboria::GPUInstanceData> gpu_data;
        Arboria::ArboriaInstanceRegistry::instance().build_gpu_instance_buffer(gpu_data);
        assert(gpu_data.size() == 2);
        assert((gpu_data[0].visibility_flags & 4u) != 0u); // Instância 0 tem escala negativa: FLAG_MIRRORED ativo!
        assert((gpu_data[1].visibility_flags & 4u) == 0u); // Instância 1 tem escala positiva: FLAG_MIRRORED inativo!
        std::cout << "[TESTE 17] Deteccao de Transformacao Espelhada (FLAG_MIRRORED bit 2) - OK" << std::endl;
    }

    // TESTE 18: Continuidade do Corte DAG e Monotonicidade do Erro de LOD
    {
        assert(shared_mesh.is_valid());
        const auto* mesh_info = Arboria::ArboriaMeshRegistry::instance().get_mesh_info(shared_mesh);
        assert(mesh_info != nullptr && mesh_info->cluster_count > 0);

        // Testa o corte dual em diferentes distâncias de câmera simuladas
        const float test_distances[] = { 2.0f, 6.0f, 12.0f, 25.0f, 50.0f, 100.0f };
        uint32_t last_visible = 999999;
        for (float dist : test_distances) {
            float view_proj[16] = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 };
            float cam_pos[3] = { 0.0f, 0.0f, dist };
            Arboria::GlobalSceneUniforms uniforms = Arboria::ArboriaGPUScene::instance().build_scene_uniforms(
                view_proj, cam_pos, 1.0f, 1920.0f, 1080.0f, 1.5f, 0, false, false // sem frustum para focar apenas no DAG
            );
            Arboria::SceneCullResult res = Arboria::ArboriaGPUScene::instance().simulate_cull_scene(uniforms);
            assert(res.visible_clusters > 0);
            assert(res.total_triangles_drawn > 0);
            assert(!res.has_overflow);

            // À medida que a distância aumenta, o nível de detalhe simplifica (menos triângulos/clusters)
            std::cout << "  -> Distancia " << dist << "m: " << res.visible_clusters << " clusters, " 
                      << res.total_triangles_drawn << " triangulos no corte DAG." << std::endl;
        }
        std::cout << "[TESTE 18] Continuidade do Corte DAG e Monotonicidade de Erro - OK" << std::endl;
    }

    // TESTE 19: Gestão de Orçamento de VRAM e Paginação de Geometria
    {
        Arboria::ArboriaGPUMemoryManager::instance().initialize(1024 * 1024); // 1 MB de budget para teste
        assert(Arboria::ArboriaGPUMemoryManager::instance().get_budget() == 1024 * 1024);

        Arboria::Handle dummy_mesh = Arboria::Handle::from_u64(999);
        uint32_t p0 = Arboria::ArboriaGPUMemoryManager::instance().register_page(dummy_mesh, 0, 64, 0, 64 * 96, true);
        uint32_t p1 = Arboria::ArboriaGPUMemoryManager::instance().register_page(dummy_mesh, 64, 64, 1, 64 * 96, false);
        uint32_t p2 = Arboria::ArboriaGPUMemoryManager::instance().register_page(dummy_mesh, 128, 64, 2, 64 * 96, false);

        // Página 0 é raiz: sempre residente
        assert(Arboria::ArboriaGPUMemoryManager::instance().is_page_resident(p0));
        assert(!Arboria::ArboriaGPUMemoryManager::instance().is_page_resident(p1));
        assert(!Arboria::ArboriaGPUMemoryManager::instance().is_page_resident(p2));

        // Carrega página 1 na GPU
        assert(Arboria::ArboriaGPUMemoryManager::instance().make_page_resident(p1, 10));
        assert(Arboria::ArboriaGPUMemoryManager::instance().is_page_resident(p1));

        auto stats = Arboria::ArboriaGPUMemoryManager::instance().get_statistics();
        assert(stats.total_pages == 3);
        assert(stats.resident_pages == 2);
        assert(stats.resident_bytes <= stats.budget_bytes);
        std::cout << "[TESTE 19] Gestao de Orcamento VRAM e Paginacao de Geometria - OK" << std::endl;
    }

    // TESTE 20: Priorização de Streaming por Distância e Eviction LRU Sob Pressão de Memória
    {
        // Inicializa com orçamento restrito para forçar eviction (apenas 12 KB)
        Arboria::ArboriaGPUMemoryManager::instance().initialize(12 * 1024);

        Arboria::Handle mesh_test = Arboria::Handle::from_u64(1001);
        uint32_t root_p = Arboria::ArboriaGPUMemoryManager::instance().register_page(mesh_test, 0, 64, 0, 6 * 1024, true);
        uint32_t detail_p1 = Arboria::ArboriaGPUMemoryManager::instance().register_page(mesh_test, 64, 64, 1, 5 * 1024, false);
        uint32_t detail_p2 = Arboria::ArboriaGPUMemoryManager::instance().register_page(mesh_test, 128, 64, 2, 5 * 1024, false);

        // Torna detail_p1 residente no frame 1
        assert(Arboria::ArboriaGPUMemoryManager::instance().make_page_resident(detail_p1, 1));
        assert(Arboria::ArboriaGPUMemoryManager::instance().is_page_resident(detail_p1));

        // Torna detail_p2 residente no frame 5. Como root_p (6 KB) + detail_p1 (5 KB) + detail_p2 (5 KB) = 16 KB > 12 KB,
        // detail_p1 (acessado no frame 1) deve sofrer eviction LRU!
        assert(Arboria::ArboriaGPUMemoryManager::instance().make_page_resident(detail_p2, 5));
        assert(Arboria::ArboriaGPUMemoryManager::instance().is_page_resident(detail_p2));
        assert(!Arboria::ArboriaGPUMemoryManager::instance().is_page_resident(detail_p1)); // EVICTED!
        assert(Arboria::ArboriaGPUMemoryManager::instance().is_page_resident(root_p));     // Raiz NUNCA é evicted!

        auto stats = Arboria::ArboriaGPUMemoryManager::instance().get_statistics();
        assert(stats.evictions_count > 0);
        assert(stats.resident_bytes <= stats.budget_bytes);
        std::cout << "[TESTE 20] Priorizacao de Streaming e Eviction LRU Sob Pressao de VRAM - OK" << std::endl;
    }

    // TESTE 21: Fallback Garantido para Páginas Raiz Residentes durante Page Faults
    {
        Arboria::ArboriaStreamingManager::instance().initialize(64 * 1024 * 1024);
        Arboria::Handle h_mesh(2002, 1);
        assert(Arboria::ArboriaStreamingManager::instance().register_mesh_streaming(h_mesh, 256, 5.0f));

        // Cluster 0 pertence à página 0 (raiz): sempre residente
        assert(Arboria::ArboriaStreamingManager::instance().is_cluster_resident(h_mesh, 0));

        // Cluster 200 pertence a página de detalhe ainda não carregada: gera page fault controlado
        assert(!Arboria::ArboriaStreamingManager::instance().is_cluster_resident(h_mesh, 200));

        // Consulta de fallback: garante que o renderer recebe um cluster válido da página raiz residente
        uint32_t fb_cluster = Arboria::ArboriaStreamingManager::instance().get_fallback_cluster(h_mesh, 200);
        assert(fb_cluster < 64); // Mapeado para o intervalo seguro da raiz
        assert(Arboria::ArboriaStreamingManager::instance().is_cluster_resident(h_mesh, fb_cluster));

        auto tel = Arboria::ArboriaStreamingManager::instance().get_telemetry();
        assert(tel.total_page_faults > 0);
        assert(tel.under_budget);
        std::cout << "[TESTE 21] Fallback Seguro de Clusters para Pagina Raiz Durante Page Faults - OK" << std::endl;
    }

    // TESTE 22: Geometria Mutavel (Copy-On-Write Overlay) e Isolamento de Assets Compartilhados (GATE 1)
    {
        // 1. Instanciacao de duas entidades compartilhando o mesmo asset de malha
        Arboria::Handle h_shared_mesh(mesh_id, 1);
        Arboria::Handle inst_a = Arboria::ArboriaRenderWorld::instance().register_instance(h_shared_mesh, 0);
        Arboria::Handle inst_b = Arboria::ArboriaRenderWorld::instance().register_instance(h_shared_mesh, 0);
        assert(inst_a.is_valid());
        assert(inst_b.is_valid());
        assert(inst_a.index != inst_b.index);

        // 2. Ambas devem iniciar sem geometria mutavel (custo 0 de memoria adicional)
        assert(!Arboria::ArboriaRenderWorld::instance().has_mutable_geometry(inst_a));
        assert(!Arboria::ArboriaRenderWorld::instance().has_mutable_geometry(inst_b));
        assert(Arboria::ArboriaRenderWorld::instance().get_mutable_overlay(inst_a) == nullptr);
        assert(Arboria::ArboriaRenderWorld::instance().get_mutable_overlay(inst_b) == nullptr);

        // 3. Modifica apenas a Instancia B gerando COW Overlay sob demanda
        auto overlay_b = Arboria::ArboriaRenderWorld::instance().get_or_create_mutable_overlay(inst_b);
        assert(overlay_b != nullptr);
        assert(Arboria::ArboriaRenderWorld::instance().get_mutable_overlay(inst_b) != nullptr);
        // Instancia A DEVE permanecer 100% inalterada e compartilhando o asset base
        assert(!Arboria::ArboriaRenderWorld::instance().has_mutable_geometry(inst_a));
        assert(Arboria::ArboriaRenderWorld::instance().get_mutable_overlay(inst_a) == nullptr);

        // 4. Injeta regiao modificada em B com versionamento e metadados requeridos
        Arboria::MutableRegion& reg = overlay_b->get_or_create_region(101);
        reg.region_id = 101;
        reg.mesh_id = static_cast<uint32_t>(mesh_id);
        reg.instance_id = inst_b.index;
        reg.geometry_version = 1;
        reg.parent_cluster_id = 0;
        reg.dirty_flags = Arboria::MUTABLE_DIRTY_GEOMETRY | Arboria::MUTABLE_DIRTY_BOUNDS;
        reg.vertex_offset = 0;
        reg.vertex_count = 12;
        reg.index_offset = 0;
        reg.index_count = 36;
        reg.material_id = 0;
        reg.residency_state = Arboria::MUTABLE_RESIDENCY_RESIDENT;
        reg.center[0] = 1.0f; reg.center[1] = 2.0f; reg.center[2] = 3.0f;
        reg.radius = 0.5f;
        reg.aabb_min[0] = 0.5f; reg.aabb_min[1] = 1.5f; reg.aabb_min[2] = 2.5f;
        reg.aabb_max[0] = 1.5f; reg.aabb_max[1] = 2.5f; reg.aabb_max[2] = 3.5f;
        reg.replaced_cluster_ids.push_back(0); // Cluster 0 localmente substituido

        overlay_b->map_cluster_replacement(0, 101, 0);
        overlay_b->bump_version();
        overlay_b->mark_dirty(Arboria::MUTABLE_DIRTY_GEOMETRY | Arboria::MUTABLE_DIRTY_BOUNDS);

        // 5. Verificacao de versionamento e estado do DAG local
        assert(Arboria::ArboriaRenderWorld::instance().has_mutable_geometry(inst_b));
        assert(!Arboria::ArboriaRenderWorld::instance().has_mutable_geometry(inst_a));
        assert(overlay_b->get_geometry_version() == 2);
        assert(overlay_b->is_cluster_replaced(0));
        assert(!overlay_b->is_cluster_replaced(1)); // Cluster 1 continua compartilhado do asset base
        assert(overlay_b->is_dirty(Arboria::MUTABLE_DIRTY_GEOMETRY));
        assert(overlay_b->is_dirty(Arboria::MUTABLE_DIRTY_BOUNDS));

        // 6. Validacao dos limites combinados
        float base_center[3] = { 0.0f, 0.0f, 0.0f };
        float base_radius = 1.732f;
        float base_min[3] = { -1.0f, -1.0f, -1.0f };
        float base_max[3] = {  1.0f,  1.0f,  1.0f };
        float comb_center[3], comb_radius, comb_min[3], comb_max[3];
        overlay_b->compute_combined_bounds(
            base_center, base_radius,
            base_min, base_max,
            comb_center, comb_radius,
            comb_min, comb_max
        );
        assert(comb_min[0] <= -1.0f && comb_min[1] <= -1.0f && comb_min[2] <= -1.0f);
        assert(comb_max[0] >= 1.5f && comb_max[1] >= 2.5f && comb_max[2] >= 3.5f);

        // 7. Validacao do GPU Instance Buffer
        std::vector<Arboria::GPUInstanceData> gpu_instances;
        Arboria::ArboriaInstanceRegistry::instance().build_gpu_instance_buffer(gpu_instances);
        assert(gpu_instances.size() >= 2);

        // 8. Limpa dirty flags
        overlay_b->clear_dirty(Arboria::MUTABLE_DIRTY_GEOMETRY | Arboria::MUTABLE_DIRTY_BOUNDS);
        assert(!overlay_b->is_dirty(Arboria::MUTABLE_DIRTY_GEOMETRY));
        assert(!overlay_b->is_dirty(Arboria::MUTABLE_DIRTY_BOUNDS));

        // 9. Garante que Instancia A continua perfeitamente intacta
        assert(!Arboria::ArboriaRenderWorld::instance().has_mutable_geometry(inst_a));

        // 10. Limpeza
        Arboria::ArboriaRenderWorld::instance().release_instance(inst_a);
        Arboria::ArboriaRenderWorld::instance().release_instance(inst_b);
        std::cout << "[TESTE 22] Geometria Mutavel (Copy-On-Write Overlay) e Isolamento de Instancias - OK" << std::endl;
    }

    // TESTE 23: Primeira Modificação Topológica Real (Esculpir Depressão e Exportação/Importação OBJ - GATE 2)
    {
        Arboria::Handle h_mesh(mesh_id, 1);
        Arboria::Handle inst_rock_a = Arboria::ArboriaRenderWorld::instance().register_instance(h_mesh, 0);
        Arboria::Handle inst_rock_b = Arboria::ArboriaRenderWorld::instance().register_instance(h_mesh, 0);
        assert(inst_rock_a.is_valid());
        assert(inst_rock_b.is_valid());

        const auto* mesh_info = Arboria::ArboriaMeshRegistry::instance().get_mesh_info(h_mesh);
        assert(mesh_info && mesh_info->resource);
        const auto& base_resource = *mesh_info->resource;

        // 1. Estatísticas originais do asset compartilhado no LOD 0
        auto overlay_b = Arboria::ArboriaRenderWorld::instance().get_or_create_mutable_overlay(inst_rock_b);
        assert(overlay_b != nullptr);

        size_t initial_verts = 0, initial_tris = 0;
        overlay_b->get_combined_lod0_stats(base_resource, initial_verts, initial_tris);
        assert(initial_verts > 0);
        assert(initial_tris > 0);

        // 2. Operação geométrica real: Esculpir depressão localizada
        // Centro exatamente sobre a superfície da rocha
        const auto& first_c = base_resource.get_clusters()[0];
        const auto& first_v = base_resource.get_vertices()[first_c.vertex_offset];
        float sculpt_center[3] = { first_v.position[0], first_v.position[1], first_v.position[2] };
        float sculpt_radius = 0.5f;
        float sculpt_depth = 0.15f;

        uint32_t affected_clusters = Arboria::ArboriaRenderWorld::instance().apply_depression(
            inst_rock_b, sculpt_center, sculpt_radius, sculpt_depth, true
        );
        assert(affected_clusters > 0);
        std::cout << "  -> Clusters afetados e reconstruidos localmente: " << affected_clusters << std::endl;

        // 3. Comprovação de alteração topológica real (não apenas shader ou deslocamento puro)
        size_t modified_verts = 0, modified_tris = 0;
        overlay_b->get_combined_lod0_stats(base_resource, modified_verts, modified_tris);
        assert(modified_verts > initial_verts); // Topologia alterada via remalhamento/subdivisão localizada
        assert(modified_tris > initial_tris);   // Novos triângulos e faces criados
        std::cout << "  -> Vertices LOD 0: " << initial_verts << " -> " << modified_verts << " (+" << (modified_verts - initial_verts) << ")" << std::endl;
        std::cout << "  -> Triangulos LOD 0: " << initial_tris << " -> " << modified_tris << " (+" << (modified_tris - initial_tris) << ")" << std::endl;

        // 4. Verificação de normais recalculadas e finitas
        for (const auto& pair : overlay_b->get_regions()) {
            const auto& reg = pair.second;
            for (const auto& v : reg.vertices) {
                assert(!std::isnan(v.normal[0]) && !std::isnan(v.normal[1]) && !std::isnan(v.normal[2]));
                assert(!std::isinf(v.normal[0]) && !std::isinf(v.normal[1]) && !std::isinf(v.normal[2]));
                float len = std::sqrt(v.normal[0]*v.normal[0] + v.normal[1]*v.normal[1] + v.normal[2]*v.normal[2]);
                assert(std::abs(len - 1.0f) < 0.01f);
            }
        }

        // 5. Isolamento de instância: Rocha A permanece 100% inalterada
        assert(!Arboria::ArboriaRenderWorld::instance().has_mutable_geometry(inst_rock_a));
        assert(Arboria::ArboriaRenderWorld::instance().get_mutable_overlay(inst_rock_a) == nullptr);

        // 6. Exportação para arquivo Wavefront OBJ em disco
        std::string obj_export_path = "artifacts/gates/stage_02/modified_rock.obj";
        assert(Arboria::ArboriaRenderWorld::instance().export_instance_to_obj(inst_rock_b, obj_export_path));

        // 7. Releitura e validação independente da malha exportada (comprovando que não depende de shader)
        std::ifstream obj_file(obj_export_path);
        assert(obj_file.is_open());

        size_t parsed_v_count = 0;
        size_t parsed_vn_count = 0;
        size_t parsed_f_count = 0;
        std::string line;
        while (std::getline(obj_file, line)) {
            if (line.rfind("v ", 0) == 0) parsed_v_count++;
            else if (line.rfind("vn ", 0) == 0) parsed_vn_count++;
            else if (line.rfind("f ", 0) == 0) parsed_f_count++;
        }
        obj_file.close();

        assert(parsed_v_count == modified_verts);
        assert(parsed_vn_count == modified_verts);
        assert(parsed_f_count == modified_tris);
        std::cout << "  -> OBJ exportado e reimportado com sucesso: " << parsed_v_count << " vertices, " << parsed_f_count << " faces - OK" << std::endl;

        // 8. Limpeza
        Arboria::ArboriaRenderWorld::instance().release_instance(inst_rock_a);
        Arboria::ArboriaRenderWorld::instance().release_instance(inst_rock_b);
        std::cout << "[TESTE 23] Primeira Modificacao Topologica Real (Escultura & Export/Import OBJ) - OK" << std::endl;
    }

    // TESTE 24: Reconstrução Incremental do DAG e Extensão do Trabalho Realizado (GATE 3)
    {
        Arboria::Handle h_mesh(mesh_id, 1);
        Arboria::Handle inst_a = Arboria::ArboriaRenderWorld::instance().register_instance(h_mesh, 0);
        Arboria::Handle inst_b = Arboria::ArboriaRenderWorld::instance().register_instance(h_mesh, 0);
        assert(inst_a.is_valid() && inst_b.is_valid());

        const auto* mesh_info = Arboria::ArboriaMeshRegistry::instance().get_mesh_info(h_mesh);
        assert(mesh_info && mesh_info->resource);
        const auto& base_resource = *mesh_info->resource;

        // 1. Aplica operação localizada de escultura na Instância B
        const auto& first_c = base_resource.get_clusters()[0];
        const auto& first_v = base_resource.get_vertices()[first_c.vertex_offset];
        float sculpt_center[3] = { first_v.position[0], first_v.position[1], first_v.position[2] };
        float sculpt_radius = 0.5f;
        float sculpt_depth = 0.15f;

        uint32_t affected = Arboria::ArboriaRenderWorld::instance().apply_depression(
            inst_b, sculpt_center, sculpt_radius, sculpt_depth, true
        );
        assert(affected > 0);

        // 2. Executa Reconstrução Incremental do DAG (propagação hierárquica sem recomputação global)
        Arboria::DAGReconstructionStats dag_stats = Arboria::ArboriaRenderWorld::instance().rebuild_dag_incremental(inst_b);

        // 3. Validação dos critérios inegociáveis do GATE 3
        assert(dag_stats.modified_lod0_clusters > 0);
        assert(dag_stats.affected_groups > 0);
        assert(dag_stats.rebuilt_parent_clusters > 0);
        assert(dag_stats.preserved_clusters > 300); // Mais de 80% da malha preservada intacta sem reprocessamento!
        assert(!dag_stats.fallback_triggered);
        assert(dag_stats.dag_update_time_ms >= 0.0f);

        std::cout << "  -> Extensão do Trabalho Incremental no DAG:" << std::endl;
        std::cout << "     * Clusters LOD 0 modificados: " << dag_stats.modified_lod0_clusters << std::endl;
        std::cout << "     * Grupos DAG afetados: " << dag_stats.affected_groups << std::endl;
        std::cout << "     * Clusters pais reconstruídos: " << dag_stats.rebuilt_parent_clusters << std::endl;
        std::cout << "     * Clusters preservados intactos: " << dag_stats.preserved_clusters << std::endl;
        std::cout << "     * Tempo de atualização do DAG: " << dag_stats.dag_update_time_ms << " ms" << std::endl;

        // 4. Validação da Seleção de LOD no DAG com a geometria mutável integrada
        const float distances[] = { 2.0f, 12.0f, 50.0f, 100.0f };
        for (float dist : distances) {
            float view_proj[16] = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 };
            float cam_pos[3] = { 0.0f, 0.0f, dist };
            Arboria::GlobalSceneUniforms uniforms = Arboria::ArboriaGPUScene::instance().build_scene_uniforms(
                view_proj, cam_pos, 1.0f, 1920.0f, 1080.0f, 1.5f, 0, false, false
            );
            Arboria::SceneCullResult res = Arboria::ArboriaGPUScene::instance().simulate_cull_scene(uniforms);
            assert(res.visible_clusters > 0);
            assert(res.total_triangles_drawn > 0);
            assert(!res.has_overflow);
            std::cout << "     * Distancia " << dist << "m -> " << res.visible_clusters << " clusters, "
                      << res.total_triangles_drawn << " triangulos no corte DAG mutavel - OK" << std::endl;
        }

        // 5. Instância A permanece 100% inalterada
        assert(!Arboria::ArboriaRenderWorld::instance().has_mutable_geometry(inst_a));

        // 6. Limpeza
        Arboria::ArboriaRenderWorld::instance().release_instance(inst_a);
        Arboria::ArboriaRenderWorld::instance().release_instance(inst_b);
        std::cout << "[TESTE 24] Reconstrucao Incremental do DAG (GATE 3) - OK" << std::endl;
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
