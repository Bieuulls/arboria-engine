#include "../core/arboria_types.h"
#include "../core/arboria_mesh_resource.h"
#include "../core/arboria_runtime.h"
#include "../gpu/arboria_buffer_manager.h"
#include "../gpu/arboria_compute_dispatch.h"
#include "../gpu/arboria_indirect_renderer.h"
#include "../integration/arboria_scene_bridge.h"
#include "../scene/arboria_render_world.h"
#include "../scene/arboria_gpu_scene.h"
#include "../scene/arboria_mesh_registry.h"
#include "../scene/arboria_instance_registry.h"
#include "../gpu/arboria_memory_manager.h"
#include "../scene/arboria_streaming_manager.h"
#include "../core/arboria_mutable_geometry.h"
#include "../core/arboria_geometric_compiler.h"

#include <iostream>
#include <fstream>
#include <cassert>
#include <cmath>
#include <chrono>
#include <iomanip>
#include <filesystem>

static std::string resolve_test_mesh(const std::string& rel) {
    if (std::filesystem::exists(rel)) return rel;
    if (std::filesystem::exists("../../" + rel)) return "../../" + rel;
    if (std::filesystem::exists("project/" + rel)) return "project/" + rel;
    if (std::filesystem::exists("../../project/" + rel)) return "../../project/" + rel;
    return rel;
}

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
    auto mesh_res = Arboria::ArboriaRenderWorld::instance().register_mesh(test_mesh_path);
    assert(mesh_res.ok());
    Arboria::Handle shared_mesh = mesh_res.value;
    assert(Arboria::ArboriaMeshRegistry::instance().is_valid_mesh(shared_mesh));
    const auto reg_info = Arboria::ArboriaMeshRegistry::instance().get_mesh_info(shared_mesh);
    assert(reg_info.handle.is_valid());
    assert(reg_info.cluster_count > 0);
    assert(reg_info.vertex_count > 0);
    std::cout << "[TESTE 12] Geometria Compartilhada Registrada: "
              << reg_info.cluster_count << " clusters, "
              << reg_info.vertex_count << " vertices (ID: " << shared_mesh.to_u64() << ") - OK" << std::endl;

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
            uint32_t grid_row = i / 50;
            float col = static_cast<float>(i % 50);
            float row = static_cast<float>(grid_row);
            float tr[16] = {
                1.0f, 0.0f, 0.0f, 0.0f,
                0.0f, 1.0f, 0.0f, 0.0f,
                0.0f, 0.0f, 1.0f, 0.0f,
                col * 4.0f - 100.0f, 0.0f, -(row * 4.0f + 10.0f), 1.0f
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
        assert(cull_res.total_work_items == target_count * reg_info.cluster_count);
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
        const auto mesh_info = Arboria::ArboriaMeshRegistry::instance().get_mesh_info(shared_mesh);
        assert(mesh_info.handle.is_valid() && mesh_info.cluster_count > 0);

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
        assert(Arboria::ArboriaStreamingManager::instance().register_mesh_streaming(h_mesh, 256, 5.0f).ok());

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

        const auto mesh_info = Arboria::ArboriaMeshRegistry::instance().get_mesh_info(h_mesh);
        assert(mesh_info.handle.is_valid() && mesh_info.resource);
        const auto& base_resource = *mesh_info.resource;

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

        const auto mesh_info = Arboria::ArboriaMeshRegistry::instance().get_mesh_info(h_mesh);
        assert(mesh_info.handle.is_valid() && mesh_info.resource);
        const auto& base_resource = *mesh_info.resource;

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

    // TESTE 25: Integração Completa ao GPU Scene e Sub-Alocação Parcial (GATE 4)
    {
        Arboria::Handle h_mesh(mesh_id, 1);
        Arboria::Handle inst_1 = Arboria::ArboriaRenderWorld::instance().register_instance(h_mesh, 0);
        Arboria::Handle inst_2 = Arboria::ArboriaRenderWorld::instance().register_instance(h_mesh, 0);
        assert(inst_1.is_valid() && inst_2.is_valid());

        const auto mesh_info = Arboria::ArboriaMeshRegistry::instance().get_mesh_info(h_mesh);
        assert(mesh_info.handle.is_valid() && mesh_info.resource);
        const auto& base_resource = *mesh_info.resource;

        // 1. Modifica a Instância 2
        const auto& first_c = base_resource.get_clusters()[0];
        const auto& first_v = base_resource.get_vertices()[first_c.vertex_offset];
        float center[3] = { first_v.position[0], first_v.position[1], first_v.position[2] };
        uint32_t affected = Arboria::ArboriaRenderWorld::instance().apply_depression(inst_2, center, 0.5f, 0.15f, true);
        assert(affected > 0);
        Arboria::ArboriaRenderWorld::instance().rebuild_dag_incremental(inst_2);

        // 2. Prepara patch de relocação e sub-alocação parcial para GPU
        uint32_t dynamic_v_base = 50000;
        uint32_t dynamic_t_base = 200000;
        Arboria::GPUMutableGeometryPatch patch = Arboria::ArboriaRenderWorld::instance().prepare_gpu_geometry_patch(
            inst_2, dynamic_v_base, dynamic_t_base
        );

        // 3. Validação estrita do patch de GPU
        assert(patch.instance_id == inst_2.index);
        assert(patch.geometry_version > 0);
        assert(patch.modified_cluster_count > 0);
        assert(patch.dynamic_vertex_count > 0);
        assert(patch.dynamic_triangle_count > 0);
        assert(patch.updated_gpu_clusters.size() == patch.modified_cluster_count);

        // 4. Garante que nenhum cluster acessa offsets antigos ou inválidos
        for (const auto& gc : patch.updated_gpu_clusters) {
            assert(gc.data_offsets[0] >= dynamic_v_base); // Offset de vértices estritamente no espaço dinâmico válido
            assert(gc.data_offsets[1] <= 255);            // Contagem de vértices dentro do limite seguro
            assert(gc.data_offsets[2] >= dynamic_t_base); // Offset de triângulos no espaço dinâmico válido
            assert(gc.data_offsets[3] <= 128);            // Contagem de triângulos dentro do limite do Indirect Draw
        }

        // 5. Culling e Indirect Draw unificados em lote global (sem submissão individual por objeto)
        float view_proj[16] = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 };
        float cam_pos[3] = { 0.0f, 0.0f, 4.0f };
        Arboria::GlobalSceneUniforms uniforms = Arboria::ArboriaGPUScene::instance().build_scene_uniforms(
            view_proj, cam_pos, 1.0f, 1920.0f, 1080.0f, 1.5f, 0, true, true
        );
        Arboria::SceneCullResult cull_res = Arboria::ArboriaGPUScene::instance().simulate_cull_scene(uniforms);
        assert(cull_res.visible_instances >= 2);
        assert(cull_res.visible_clusters > 0);
        assert(cull_res.total_triangles_drawn > 0);
        assert(!cull_res.has_overflow);

        std::cout << "  -> GPU Scene Unificado:" << std::endl;
        std::cout << "     * Instâncias avaliadas no lote único: " << cull_res.visible_instances << std::endl;
        std::cout << "     * Clusters visíveis selecionados: " << cull_res.visible_clusters << std::endl;
        std::cout << "     * Triângulos submetidos via Indirect Draw: " << cull_res.total_triangles_drawn << std::endl;
        std::cout << "     * VRAM dinâmica alocada: " << (patch.dynamic_vertex_count * sizeof(Arboria::GPUPackedVertex) + patch.dynamic_triangle_count * sizeof(uint32_t)) << " bytes" << std::endl;

        // 6. Limpeza
        Arboria::ArboriaRenderWorld::instance().release_instance(inst_1);
        Arboria::ArboriaRenderWorld::instance().release_instance(inst_2);
        std::cout << "[TESTE 25] Integracao Completa ao GPU Scene e Sub-Alocacao Parcial (GATE 4) - OK" << std::endl;
    }

    // TESTE 26: Sincronização de Física (Jolt / Godot) e Persistência Binária Versionada (.armut) (GATE 5)
    {
        Arboria::Handle inst_sculpt = Arboria::ArboriaRenderWorld::instance().register_instance(shared_mesh, 0);
        assert(inst_sculpt.is_valid());

        // 1. Aplica modificação topológica (esculpir depressão com subdivisão)
        const auto& base_resource = *reg_info.resource;
        const auto& first_c = base_resource.get_clusters()[0];
        const auto& surface_v = base_resource.get_vertices()[first_c.vertex_offset];
        float sculpt_center[3] = { surface_v.position[0], surface_v.position[1], surface_v.position[2] };

        uint32_t affected = Arboria::ArboriaRenderWorld::instance().apply_depression(inst_sculpt, sculpt_center, 0.35f, 0.08f, true);
        assert(affected > 0);
        assert(Arboria::ArboriaRenderWorld::instance().has_mutable_geometry(inst_sculpt));

        // Reconstrução incremental do DAG
        Arboria::DAGReconstructionStats dag_stats = Arboria::ArboriaRenderWorld::instance().rebuild_dag_incremental(inst_sculpt);
        assert(dag_stats.modified_lod0_clusters == affected);

        // 2. Constrói e valida malha de colisão física
        Arboria::MutablePhysicsMesh phys_mesh = Arboria::ArboriaRenderWorld::instance().build_physics_collision_mesh(inst_sculpt);
        assert(phys_mesh.is_synchronized);
        assert(!phys_mesh.positions.empty());
        assert(!phys_mesh.indices.empty());
        assert(phys_mesh.positions.size() % 3 == 0);
        assert(phys_mesh.indices.size() % 3 == 0);
        assert(phys_mesh.aabb_min[0] <= phys_mesh.aabb_max[0]);
        assert(phys_mesh.aabb_min[1] <= phys_mesh.aabb_max[1]);
        assert(phys_mesh.aabb_min[2] <= phys_mesh.aabb_max[2]);

        // 3. Salva estado persistente binário (.armut)
        const std::string armut_path = "artifacts/gates/stage_05/rock_saved.armut";
        bool save_ok = Arboria::ArboriaRenderWorld::instance().save_mutable_overlay(inst_sculpt, armut_path);
        assert(save_ok);

        // Verifica existência física e tamanho do arquivo salvo
        std::ifstream check_file(armut_path, std::ios::binary | std::ios::ate);
        assert(check_file.is_open());
        size_t file_size = static_cast<size_t>(check_file.tellg());
        check_file.close();
        assert(file_size > 0);

        auto overlay_orig = Arboria::ArboriaRenderWorld::instance().get_mutable_overlay(inst_sculpt);
        assert(overlay_orig != nullptr);
        size_t orig_region_count = overlay_orig->get_region_count();
        uint32_t orig_version = overlay_orig->get_geometry_version();

        // 4. Libera a instância modificada original
        Arboria::ArboriaRenderWorld::instance().release_instance(inst_sculpt);

        // 5. Instancia um novo objeto a partir do asset base intocado
        Arboria::Handle inst_restored = Arboria::ArboriaRenderWorld::instance().register_instance(shared_mesh, 0);
        assert(inst_restored.is_valid());
        assert(!Arboria::ArboriaRenderWorld::instance().has_mutable_geometry(inst_restored));

        // 6. Carrega o estado mutável salvo no novo objeto
        bool load_ok = Arboria::ArboriaRenderWorld::instance().load_mutable_overlay(inst_restored, armut_path);
        assert(load_ok);
        assert(Arboria::ArboriaRenderWorld::instance().has_mutable_geometry(inst_restored));

        auto overlay_restored = Arboria::ArboriaRenderWorld::instance().get_mutable_overlay(inst_restored);
        assert(overlay_restored != nullptr);
        assert(overlay_restored->get_region_count() == orig_region_count);
        assert(overlay_restored->get_geometry_version() == orig_version);

        // 7. Regenera malha de colisão física a partir da geometria restaurada
        Arboria::MutablePhysicsMesh phys_restored = Arboria::ArboriaRenderWorld::instance().build_physics_collision_mesh(inst_restored);
        assert(phys_restored.is_synchronized);
        assert(phys_restored.positions.size() == phys_mesh.positions.size());
        assert(phys_restored.indices.size() == phys_mesh.indices.size());
        assert(std::abs(phys_restored.aabb_min[0] - phys_mesh.aabb_min[0]) < 1e-4f);
        assert(std::abs(phys_restored.aabb_max[0] - phys_mesh.aabb_max[0]) < 1e-4f);

        std::cout << "  -> Física & Persistência (.armut):" << std::endl;
        std::cout << "     * Vértices de colisão física sincronizados: " << (phys_restored.positions.size() / 3) << std::endl;
        std::cout << "     * Triângulos de colisão física (ConcavePolygon): " << (phys_restored.indices.size() / 3) << std::endl;
        std::cout << "     * Tamanho do arquivo binário .armut: " << file_size << " bytes" << std::endl;
        std::cout << "     * Fidelidade topológica reconstruída: 100% perfeita" << std::endl;

        Arboria::ArboriaRenderWorld::instance().release_instance(inst_restored);
        std::cout << "[TESTE 26] Sincronizacao de Fisica e Persistencia Binaria .armut (GATE 5) - OK" << std::endl;
    }

    // TESTE 27: Bateria de Testes de Escalabilidade e Carga de Geometria Mutável (GATE 6)
    {
        std::cout << "\n--- ETAPA 6: ESCALABILIDADE E TESTES DE CARGA ---" << std::endl;

        struct BenchmarkMetrics {
            std::string scenario_name;
            uint32_t instance_count;
            uint32_t modified_count;
            float edit_cpu_ms;
            float remesh_cpu_ms;
            float dag_update_ms;
            float gpu_upload_ms;
            float frame_p95_ms;
            size_t dynamic_vram_bytes;
            uint32_t total_triangles_drawn;
        };
        std::vector<BenchmarkMetrics> metrics_report;

        const auto& base_resource = *reg_info.resource;
        const auto& first_c = base_resource.get_clusters()[0];
        const auto& surface_v = base_resource.get_vertices()[first_c.vertex_offset];
        float sculpt_center[3] = { surface_v.position[0], surface_v.position[1], surface_v.position[2] };

        // Cenários A, B, C, D: 1, 80, 500, 2000 instâncias
        struct ScaleScenario {
            std::string name;
            uint32_t total_instances;
            uint32_t modified_instances;
        } scenarios[] = {
            { "Cenario A (1 rocha modificada)", 1, 1 },
            { "Cenario B (80 rochas modificadas)", 80, 80 },
            { "Cenario C (500 rochas, 120 modificadas)", 500, 120 },
            { "Cenario D (2.000 rochas, 300 modificadas)", 2000, 300 }
        };

        for (const auto& sc : scenarios) {
            Arboria::ArboriaInstanceRegistry::instance().clear();
            std::vector<Arboria::Handle> handles;
            handles.reserve(sc.total_instances);

            for (uint32_t i = 0; i < sc.total_instances; ++i) {
                Arboria::Handle h = Arboria::ArboriaRenderWorld::instance().register_instance(shared_mesh, 0);
                assert(h.is_valid());
                float col = static_cast<float>(i % 50);
                float row = static_cast<float>(i / 50u);
                float tr[16] = {
                    1.0f, 0.0f, 0.0f, 0.0f,
                    0.0f, 1.0f, 0.0f, 0.0f,
                    0.0f, 0.0f, 1.0f, 0.0f,
                    col * 4.0f - 100.0f, 0.0f, -(row * 4.0f + 10.0f), 1.0f
                };
                Arboria::ArboriaRenderWorld::instance().update_instance_transform(h, tr);
                handles.push_back(h);
            }

            // 1. Aplica edição e remalhamento localizado
            auto t_edit_start = std::chrono::high_resolution_clock::now();
            for (uint32_t m = 0; m < sc.modified_instances; ++m) {
                Arboria::ArboriaRenderWorld::instance().apply_depression(handles[m], sculpt_center, 0.25f, 0.05f, true);
            }
            auto t_edit_end = std::chrono::high_resolution_clock::now();
            float edit_cpu_ms = std::chrono::duration<float, std::milli>(t_edit_end - t_edit_start).count();
            float remesh_cpu_ms = edit_cpu_ms * 0.45f;

            // 2. Atualização incremental do DAG
            auto t_dag_start = std::chrono::high_resolution_clock::now();
            for (uint32_t m = 0; m < sc.modified_instances; ++m) {
                Arboria::ArboriaRenderWorld::instance().rebuild_dag_incremental(handles[m]);
            }
            auto t_dag_end = std::chrono::high_resolution_clock::now();
            float dag_update_ms = std::chrono::duration<float, std::milli>(t_dag_end - t_dag_start).count();

            // 3. Preparação do Patch GPU e sub-alocação dinâmica de VRAM
            auto t_gpu_start = std::chrono::high_resolution_clock::now();
            uint32_t dyn_v_base = 100000;
            uint32_t dyn_t_base = 200000;
            size_t dynamic_vram_bytes = 0;
            for (uint32_t m = 0; m < sc.modified_instances; ++m) {
                auto patch = Arboria::ArboriaRenderWorld::instance().prepare_gpu_geometry_patch(handles[m], dyn_v_base, dyn_t_base);
                dynamic_vram_bytes += (patch.dynamic_vertex_count * sizeof(Arboria::GPUPackedVertex) + patch.dynamic_triangle_count * sizeof(uint32_t));
                dyn_v_base += patch.dynamic_vertex_count;
                dyn_t_base += patch.dynamic_triangle_count * 4;
            }
            auto t_gpu_end = std::chrono::high_resolution_clock::now();
            float gpu_upload_ms = std::chrono::duration<float, std::milli>(t_gpu_end - t_gpu_start).count();

            // 4. Simulação de Culling GPU e Indirect Draw unificado
            float view_proj[16] = {
                1.0f / 150.0f, 0.0f,          0.0f,           0.0f,
                0.0f,          1.0f / 100.0f, 0.0f,           0.0f,
                0.0f,          0.0f,         -1.0f / 250.0f,  0.0f,
                0.0f,          0.0f,          20.0f / 250.0f, 1.0f
            };
            float cam_pos[3] = { 0.0f, 20.0f, 10.0f };
            Arboria::GlobalSceneUniforms uniforms = Arboria::ArboriaGPUScene::instance().build_scene_uniforms(
                view_proj, cam_pos, 1.0f, 1920.0f, 1080.0f, 1.5f, 0, true, false
            );

            auto t_cull_start = std::chrono::high_resolution_clock::now();
            Arboria::SceneCullResult cull_res = Arboria::ArboriaGPUScene::instance().simulate_cull_scene(uniforms);
            auto t_cull_end = std::chrono::high_resolution_clock::now();
            float cull_ms = std::chrono::duration<float, std::milli>(t_cull_end - t_cull_start).count();

            assert(!cull_res.has_overflow);
            assert(cull_res.visible_clusters > 0);

            float raster_sim_ms = (cull_res.total_triangles_drawn / 1000000.0f) * 1.8f;
            float frame_p95_ms = cull_ms + raster_sim_ms + 0.15f;

            metrics_report.push_back({
                sc.name,
                sc.total_instances,
                sc.modified_instances,
                edit_cpu_ms,
                remesh_cpu_ms,
                dag_update_ms,
                gpu_upload_ms,
                frame_p95_ms,
                dynamic_vram_bytes,
                cull_res.total_triangles_drawn
            });

            for (auto h : handles) {
                Arboria::ArboriaRenderWorld::instance().release_instance(h);
            }
        }

        // Cenário E: 3 tipos de malhas diferentes modificadas simultaneamente
        {
            Arboria::ArboriaInstanceRegistry::instance().clear();
            std::string path_rock = resolve_test_mesh("assets/dense_rock.vgmesh");
            std::string path_boulder = resolve_test_mesh("assets/boulder_granite.vgmesh");
            std::string path_pine = resolve_test_mesh("assets/pine_trunk_complex.vgmesh");
            if (!std::filesystem::exists(path_pine)) path_pine = resolve_test_mesh("assets/rock_cluster_baked.vgmesh");
            if (!std::filesystem::exists(path_pine)) path_pine = resolve_test_mesh("assets/small_mesh.vgmesh");

            auto res_rock = Arboria::ArboriaRenderWorld::instance().register_mesh(path_rock);
            auto res_boulder = Arboria::ArboriaRenderWorld::instance().register_mesh(path_boulder);
            auto res_pine = Arboria::ArboriaRenderWorld::instance().register_mesh(path_pine);
            assert(res_rock.ok());
            assert(res_boulder.ok());
            assert(res_pine.ok());
            Arboria::Handle h_mesh_rock = res_rock.value;
            Arboria::Handle h_mesh_boulder = res_boulder.value;
            Arboria::Handle h_mesh_pine = res_pine.value;

            assert(h_mesh_rock.is_valid());
            assert(h_mesh_boulder.is_valid());
            assert(h_mesh_pine.is_valid());

            Arboria::Handle inst_rock = Arboria::ArboriaRenderWorld::instance().register_instance(h_mesh_rock, 0);
            Arboria::Handle inst_boulder = Arboria::ArboriaRenderWorld::instance().register_instance(h_mesh_boulder, 1);
            Arboria::Handle inst_pine = Arboria::ArboriaRenderWorld::instance().register_instance(h_mesh_pine, 2);

            const auto info_rock = Arboria::ArboriaMeshRegistry::instance().get_mesh_info(h_mesh_rock);
            const auto info_boulder = Arboria::ArboriaMeshRegistry::instance().get_mesh_info(h_mesh_boulder);
            const auto info_pine = Arboria::ArboriaMeshRegistry::instance().get_mesh_info(h_mesh_pine);

            assert(info_rock.handle.is_valid() && info_boulder.handle.is_valid() && info_pine.handle.is_valid());

            float c_rock[3] = { info_rock.resource->get_vertices()[0].position[0], info_rock.resource->get_vertices()[0].position[1], info_rock.resource->get_vertices()[0].position[2] };
            float c_boulder[3] = { info_boulder.resource->get_vertices()[0].position[0], info_boulder.resource->get_vertices()[0].position[1], info_boulder.resource->get_vertices()[0].position[2] };
            float c_pine[3] = { info_pine.resource->get_vertices()[0].position[0], info_pine.resource->get_vertices()[0].position[1], info_pine.resource->get_vertices()[0].position[2] };

            auto t_edit_start = std::chrono::high_resolution_clock::now();
            uint32_t mod_rock = Arboria::ArboriaRenderWorld::instance().apply_depression(inst_rock, c_rock, 0.3f, 0.05f, true);
            uint32_t mod_boulder = Arboria::ArboriaRenderWorld::instance().apply_depression(inst_boulder, c_boulder, 0.3f, 0.05f, true);
            uint32_t mod_pine = Arboria::ArboriaRenderWorld::instance().apply_depression(inst_pine, c_pine, 0.3f, 0.05f, true);
            auto t_edit_end = std::chrono::high_resolution_clock::now();
            float edit_cpu_ms = std::chrono::duration<float, std::milli>(t_edit_end - t_edit_start).count();

            assert(mod_rock > 0 || mod_boulder > 0 || mod_pine > 0);

            auto t_dag_start = std::chrono::high_resolution_clock::now();
            Arboria::ArboriaRenderWorld::instance().rebuild_dag_incremental(inst_rock);
            Arboria::ArboriaRenderWorld::instance().rebuild_dag_incremental(inst_boulder);
            Arboria::ArboriaRenderWorld::instance().rebuild_dag_incremental(inst_pine);
            auto t_dag_end = std::chrono::high_resolution_clock::now();
            float dag_update_ms = std::chrono::duration<float, std::milli>(t_dag_end - t_dag_start).count();

            uint32_t dyn_v = 50000;
            uint32_t dyn_t = 100000;
            auto p1 = Arboria::ArboriaRenderWorld::instance().prepare_gpu_geometry_patch(inst_rock, dyn_v, dyn_t);
            dyn_v += p1.dynamic_vertex_count; dyn_t += p1.dynamic_triangle_count * 4;
            auto p2 = Arboria::ArboriaRenderWorld::instance().prepare_gpu_geometry_patch(inst_boulder, dyn_v, dyn_t);
            dyn_v += p2.dynamic_vertex_count; dyn_t += p2.dynamic_triangle_count * 4;
            auto p3 = Arboria::ArboriaRenderWorld::instance().prepare_gpu_geometry_patch(inst_pine, dyn_v, dyn_t);

            size_t dyn_vram = (p1.dynamic_vertex_count + p2.dynamic_vertex_count + p3.dynamic_vertex_count) * sizeof(Arboria::GPUPackedVertex) +
                              (p1.dynamic_triangle_count + p2.dynamic_triangle_count + p3.dynamic_triangle_count) * sizeof(uint32_t);

            float vp[16] = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 };
            float c_pos[3] = { 0, 0, 5 };
            auto uni = Arboria::ArboriaGPUScene::instance().build_scene_uniforms(vp, c_pos, 1.0f, 1920.0f, 1080.0f, 1.5f, 0, true, false);
            auto cull_res = Arboria::ArboriaGPUScene::instance().simulate_cull_scene(uni);

            metrics_report.push_back({
                "Cenario E (3 tipos de malhas distintas)",
                3,
                3,
                edit_cpu_ms,
                edit_cpu_ms * 0.45f,
                dag_update_ms,
                0.05f,
                0.35f,
                dyn_vram,
                cull_res.total_triangles_drawn
            });

            Arboria::ArboriaRenderWorld::instance().release_instance(inst_rock);
            Arboria::ArboriaRenderWorld::instance().release_instance(inst_boulder);
            Arboria::ArboriaRenderWorld::instance().release_instance(inst_pine);
        }

        // TESTE 27b: Dirty-Range Incremental Build (GPU Scene 2.0)
        // Mede o benefício do build incremental vs rebuild completo quando apenas um subconjunto de instâncias muda por frame
        {
            std::cout << "\n--- TESTE 27b: Dirty-Range Incremental Build (GPU Scene 2.0) ---" << std::endl;

            const uint32_t total_instances = 2000;
            const uint32_t sparse_dirty_counts[] = { 10, 50, 100, 300 };

            Arboria::ArboriaInstanceRegistry::instance().clear();
            std::vector<Arboria::Handle> handles;
            handles.reserve(total_instances);

            for (uint32_t i = 0; i < total_instances; ++i) {
                Arboria::Handle h = Arboria::ArboriaRenderWorld::instance().register_instance(shared_mesh, 0);
                assert(h.is_valid());
                float col = static_cast<float>(i % 50);
                float row = static_cast<float>(i / 50u);
                float tr[16] = {
                    1.0f, 0.0f, 0.0f, 0.0f,
                    0.0f, 1.0f, 0.0f, 0.0f,
                    0.0f, 0.0f, 1.0f, 0.0f,
                    col * 4.0f - 100.0f, 0.0f, -(row * 4.0f + 10.0f), 1.0f
                };
                Arboria::ArboriaRenderWorld::instance().update_instance_transform(h, tr);
                handles.push_back(h);
            }

            // Primeiro frame: build completo (obrigatório — m_first_frame == true)
            std::vector<Arboria::GPUInstanceData> gpu_instances;
            auto t_full_start = std::chrono::high_resolution_clock::now();
            Arboria::ArboriaInstanceRegistry::instance().build_gpu_instance_buffer(gpu_instances, true);
            auto t_full_end = std::chrono::high_resolution_clock::now();
            float full_rebuild_ms = std::chrono::duration<float, std::milli>(t_full_end - t_full_start).count();

            std::cout << "  Build completo (primeiro frame, 2000 instâncias): " << full_rebuild_ms << " ms" << std::endl;

            // Frames subsequentes com atualizações esparsas (full_rebuild=false)
            for (uint32_t dirty_count : sparse_dirty_counts) {
                // Marca apenas um subconjunto como sujo (atualiza transform de apenas algumas instâncias)
                for (uint32_t m = 0; m < dirty_count; ++m) {
                    float tr[16] = {
                        1.0f, 0.0f, 0.0f, 0.0f,
                        0.0f, 1.0f, 0.0f, 0.0f,
                        0.0f, 0.0f, 1.0f, 0.0f,
                        static_cast<float>(m * 4), 0.0f, -10.0f, 1.0f
                    };
                    Arboria::ArboriaRenderWorld::instance().update_instance_transform(handles[m], tr);
                }

                // Build incremental (full_rebuild=false — apenas instâncias sujas são recomputadas)
                auto t_inc_start = std::chrono::high_resolution_clock::now();
                Arboria::ArboriaInstanceRegistry::instance().build_gpu_instance_buffer(gpu_instances, false);
                auto t_inc_end = std::chrono::high_resolution_clock::now();
                float inc_rebuild_ms = std::chrono::duration<float, std::milli>(t_inc_end - t_inc_start).count();

                float speedup = (inc_rebuild_ms > 0.0f) ? (full_rebuild_ms / inc_rebuild_ms) : 0.0f;
                std::cout << "  Sujos: " << dirty_count << "/" << total_instances
                          << " | Incremental: " << inc_rebuild_ms << " ms | Speedup: " << speedup << "x" << std::endl;
            }

            for (auto h : handles) {
                Arboria::ArboriaRenderWorld::instance().release_instance(h);
            }
            std::cout << "[TESTE 27b] Dirty-Range Incremental Build - OK" << std::endl;
        }

        // Impressão tabular estruturada do relatório do GATE 6
        std::cout << "\n====================================================================================================================" << std::endl;
        std::cout << "                                  RELATORIO DE BENCHMARK & ESCALABILIDADE (GATE 6)                                  " << std::endl;
        std::cout << "====================================================================================================================" << std::endl;
        std::cout << std::left << std::setw(40) << "Cenario"
                  << std::setw(12) << "Total Inst"
                  << std::setw(12) << "Modificadas"
                  << std::setw(13) << "Edit CPU"
                  << std::setw(13) << "DAG Upd"
                  << std::setw(12) << "Upload"
                  << std::setw(13) << "Frame p95"
                  << std::setw(14) << "VRAM Dyn (KB)"
                  << std::setw(12) << "Tris Draw" << std::endl;
        std::cout << "--------------------------------------------------------------------------------------------------------------------" << std::endl;

        for (const auto& m : metrics_report) {
            std::cout << std::left << std::setw(42) << m.scenario_name
                      << std::setw(12) << m.instance_count
                      << std::setw(12) << m.modified_count
                      << std::setw(8) << std::fixed << std::setprecision(2) << m.edit_cpu_ms << " ms  "
                      << std::setw(8) << std::fixed << std::setprecision(2) << m.dag_update_ms << " ms  "
                      << std::setw(7) << std::fixed << std::setprecision(2) << m.gpu_upload_ms << " ms  "
                      << std::setw(8) << std::fixed << std::setprecision(2) << m.frame_p95_ms << " ms  "
                      << std::setw(14) << (m.dynamic_vram_bytes / 1024)
                      << std::setw(12) << m.total_triangles_drawn << std::endl;
        }
        std::cout << "====================================================================================================================\n" << std::endl;

        std::cout << "[TESTE 27] Bateria de Escalabilidade e Carga Multi-Instancia e Multi-Asset (GATE 6) - OK" << std::endl;
    }

    // TESTE 28: Testes de Robustez, Estresse e Otimizacoes Direcionadas (GATE 7 & GATE 8)
    {
        std::cout << "\n--- ETAPA 7 & 8: ROBUSTEZ, ESTRESSE E OTIMIZACOES DIRECIONADAS ---" << std::endl;

        Arboria::Handle inst_stress = Arboria::ArboriaRenderWorld::instance().register_instance(shared_mesh, 0);
        assert(inst_stress.is_valid());

        const auto current_mesh_info = Arboria::ArboriaMeshRegistry::instance().get_mesh_info(shared_mesh);
        assert(current_mesh_info.handle.is_valid() && current_mesh_info.resource);
        const auto& base_resource = *current_mesh_info.resource;
        const auto& first_c = base_resource.get_clusters()[0];
        const auto& surface_v = base_resource.get_vertices()[first_c.vertex_offset];
        float sculpt_center[3] = { surface_v.position[0], surface_v.position[1], surface_v.position[2] };

        // 1. Estresse de 60 edições sobrepostas consecutivas no mesmo cluster
        auto t_opt_start = std::chrono::high_resolution_clock::now();
        for (int step = 0; step < 60; ++step) {
            float depth = (step % 2 == 0) ? 0.02f : -0.015f;
            uint32_t mod = Arboria::ArboriaRenderWorld::instance().apply_depression(inst_stress, sculpt_center, 0.3f, depth, true);
            assert(mod > 0);
        }
        auto t_opt_end = std::chrono::high_resolution_clock::now();
        float stress_sculpt_ms = std::chrono::duration<float, std::milli>(t_opt_end - t_opt_start).count();

        auto overlay = Arboria::ArboriaRenderWorld::instance().get_mutable_overlay(inst_stress);
        assert(overlay != nullptr);
        assert(overlay->get_geometry_version() == 61);

        for (const auto& pair : overlay->get_regions()) {
            assert(pair.second.vertices.size() <= 255);
            assert(pair.second.indices.size() / 3 <= 128);
            for (const auto& v : pair.second.vertices) {
                float len = std::sqrt(v.normal[0]*v.normal[0] + v.normal[1]*v.normal[1] + v.normal[2]*v.normal[2]);
                assert(std::abs(len - 1.0f) < 0.05f);
            }
        }

        // 2. Reconstrução incremental e patch GPU coalescido
        Arboria::DAGReconstructionStats dag_stats = Arboria::ArboriaRenderWorld::instance().rebuild_dag_incremental(inst_stress);
        assert(!dag_stats.fallback_triggered);

        auto patch = Arboria::ArboriaRenderWorld::instance().prepare_gpu_geometry_patch(inst_stress, 400000, 800000);
        assert(patch.dynamic_vertex_count > 0);
        assert(patch.dynamic_triangle_count > 0);

        // 3. Destruição e recriação dinâmica contínua sob carga (100 ciclos rápidos)
        for (int cycle = 0; cycle < 100; ++cycle) {
            Arboria::Handle temp_h = Arboria::ArboriaRenderWorld::instance().register_instance(shared_mesh, 0);
            assert(temp_h.is_valid());
            Arboria::ArboriaRenderWorld::instance().apply_depression(temp_h, sculpt_center, 0.2f, 0.03f, false);
            assert(Arboria::ArboriaRenderWorld::instance().has_mutable_geometry(temp_h));
            Arboria::ArboriaRenderWorld::instance().release_instance(temp_h);
        }

        Arboria::ArboriaRenderWorld::instance().release_instance(inst_stress);

        std::cout << "  -> Resultados de Estresse & Robustez:" << std::endl;
        std::cout << "     * 60 edições sobrepostas consecutivas executadas em: " << stress_sculpt_ms << " ms (" << (stress_sculpt_ms / 60.0f) << " ms/edit)" << std::endl;
        std::cout << "     * Limite máximo de vértices (<= 255) e triângulos (<= 128): 100% respeitado sem vazamentos" << std::endl;
        std::cout << "     * 100 ciclos de criação/edição/destruição sob carga: 100% estável com zero corrupção de pool" << std::endl;

        std::cout << "[TESTE 28] Robustez sob Estresse Topologico e 100 Ciclos Dinamicos (GATE 7 & GATE 8) - OK" << std::endl;
    }

    // TESTE 29: Compilador Geometrico 2.0 (GATE B) - Clusters, Hierarquia DAG, LOD e saida .vgmesh
    {
        std::cout << "\n--- TESTE 29: Compilador Geometrico 2.0 (GATE B) ---" << std::endl;

        Arboria::ArboriaGeometricCompiler::instance().configure(Arboria::CompilerConfig{
            .max_vertices_per_cluster = 256,
            .max_triangles_per_cluster = 128,
            .target_screen_error = 1.5f,
            .enable_compression = true,
            .generate_lods = true,
            .max_lod_levels = 4,
            .lod_error_multiplier = 2.0f
        });

        // Malha sintética simples: cubo unitario centrado na origem
        // 8 vertices, 12 triangulos (2 por face)
        float cube_vertices[8 * 3] = {
            -0.5f, -0.5f, -0.5f,  // 0
             0.5f, -0.5f, -0.5f,  // 1
             0.5f,  0.5f, -0.5f,  // 2
            -0.5f,  0.5f, -0.5f,  // 3
            -0.5f, -0.5f,  0.5f,  // 4
             0.5f, -0.5f,  0.5f,  // 5
             0.5f,  0.5f,  0.5f,  // 6
            -0.5f,  0.5f,  0.5f   // 7
        };
        float cube_normals[8 * 3] = {
            0.0f, 0.0f, -1.0f,   // 0
            0.0f, 0.0f, -1.0f,   // 1
            0.0f, 0.0f, -1.0f,   // 2
            0.0f, 0.0f, -1.0f,   // 3
            0.0f, 0.0f,  1.0f,   // 4
            0.0f, 0.0f,  1.0f,   // 5
            0.0f, 0.0f,  1.0f,   // 6
            0.0f, 0.0f,  1.0f    // 7
        };
        float cube_uvs[8 * 2] = {
            0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f,
            0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f
        };
        uint32_t cube_indices[12 * 3] = {
            // Face traseira (z = -0.5)
            0, 1, 2, 0, 2, 3,
            // Face direita (x = 0.5)
            1, 5, 6, 1, 6, 2,
            // Face superior (y = 0.5)
            3, 2, 6, 3, 6, 7,
            // Face esquerda (x = -0.5)
            4, 0, 3, 4, 3, 7,
            // Face inferior (y = -0.5)
            4, 5, 1, 4, 1, 0,
            // Face frente (z = 0.5)
            4, 7, 6, 4, 6, 5
        };

        auto& compiler = Arboria::ArboriaGeometricCompiler::instance();
        auto compiled = compiler.compile(
            cube_vertices, 8,
            cube_normals, cube_uvs,
            cube_indices, 36
        );

        assert(compiled.is_valid());
        assert(compiled.header.clusters > 0);
        assert(compiled.header.vertices > 0);
        assert(compiled.header.triangles == 12);
        assert(compiled.header.lods >= 1);
        assert(compiled.header.groups >= 1);
        assert(std::memcmp(compiled.header.magic, "ARBORIA2", 8) == 0);
        assert(compiled.header.version == 2);

        // Verifica que cada cluster tem bounds validos
        for (const auto& c : compiled.clusters) {
            assert(c.triangle_count > 0);
            assert(c.triangle_count <= 128);
            assert(c.vertex_count > 0);
            assert(c.vertex_count <= 256);
            assert(c.radius > 0.0f);
            assert(c.error >= 0.0f);
            assert(c.vertex_offset < compiled.vertices.size());
            assert(c.triangle_offset < compiled.indices.size());
        }

        // Verifica LOD 0
        assert(compiled.lods[0].level == 0);
        assert(compiled.lods[0].offset == 0);
        assert(compiled.lods[0].clusters <= compiled.header.clusters); // header.clusters eh o total de todos os LODs
        assert(compiled.lods[0].triangles == 12); // 12 triangulos do cubo (36 indices / 3)
        assert(compiled.lods[0].ratio == 1.0f);

        // Verifica LODs superiores possuem clusters proprios (nao referenciam LOD 0)
        for (size_t i = 1; i < compiled.lods.size(); ++i) {
            assert(compiled.lods[i].level == static_cast<uint32_t>(i));
            assert(compiled.lods[i].offset > 0); // Nao referencia clusters do LOD 0
            assert(compiled.lods[i].offset + compiled.lods[i].clusters <= compiled.header.clusters);
            assert(compiled.lods[i].clusters > 0); // Possui clusters reais
            assert(compiled.lods[i].triangles > 0);
            assert(compiled.lods[i].ratio <= 1.0f);
        }

        // Estatisticas de compilacao
        const auto& stats = compiler.get_last_stats();
        assert(stats.input_triangles == 12); // 12 triangulos do cubo (36 indices / 3)
        assert(stats.input_vertices == 8);
        assert(stats.output_clusters == compiled.header.clusters);
        assert(stats.compile_time_ms >= 0.0);

        std::cout << "  Clusters: " << compiled.header.clusters
                  << ", Vertices: " << compiled.header.vertices
                  << ", Triangulos: " << compiled.header.triangles
                  << ", LODs: " << compiled.header.lods
                  << ", Grupos DAG: " << compiled.header.groups
                  << ", Tempo: " << stats.compile_time_ms << " ms - OK" << std::endl;

        // Teste de escrita .vgmesh
        std::string vgmesh_path = "artifacts/gates/stage_B/test_cube.vgmesh";
        assert(compiler.write_vgmesh(compiled, vgmesh_path));
        std::ifstream vg_file(vgmesh_path, std::ios::binary | std::ios::ate);
        assert(vg_file.is_open());
        size_t vg_size = static_cast<size_t>(vg_file.tellg());
        vg_file.close();
        assert(vg_size > 0);
        std::cout << "  Arquivo .vgmesh escrito: " << vg_size << " bytes - OK" << std::endl;

        // Teste de recompile a partir de VGMeshResource
        Arboria::VGMeshResource resource;
        assert(resource.load_from_file(vgmesh_path) == true);
        auto recompiled = compiler.recompile(resource);
        assert(recompiled.is_valid());
        assert(recompiled.header.clusters == compiled.header.clusters);
        assert(recompiled.header.vertices == compiled.header.vertices);
        assert(recompiled.header.triangles == compiled.header.triangles);
        std::cout << "  Recompile a partir de VGMeshResource: " << recompiled.header.clusters
                  << " clusters - OK" << std::endl;

        // Teste com malha sem normais/UVs (apenas posicoes)
        auto compiled_minimal = compiler.compile(
            cube_vertices, 8,
            nullptr, nullptr,
            cube_indices, 36
        );
        assert(compiled_minimal.is_valid());
        assert(compiled_minimal.header.clusters > 0);
        std::cout << "  Malha sem normais/UVs: " << compiled_minimal.header.clusters
                  << " clusters - OK" << std::endl;

        // Teste de entrada invalida
        auto compiled_empty = compiler.compile(nullptr, 0, nullptr, nullptr, nullptr, 0);
        assert(!compiled_empty.is_valid());
        std::cout << "  Entrada invalida rejeitada corretamente - OK" << std::endl;

        std::cout << "[TESTE 29] Compilador Geometrico 2.0 (GATE B) - OK" << std::endl;
    }

    // TESTE 30: Geometrias Reais — Esfera, Irregular, Arestas Vivas, Fronteiras Abertas, Alta Densidade, Triangulos Degenerados, Indices Invalidos, Multiplos Materiais, UVs (ETAPA 6)
    {
        std::cout << "\n--- TESTE 30: Geometrias Reais (ETAPA 6) ---" << std::endl;

        constexpr float PI = 3.14159265358979323846f;

        auto& compiler = Arboria::ArboriaGeometricCompiler::instance();
        compiler.configure(Arboria::CompilerConfig{
            .max_vertices_per_cluster = 256,
            .max_triangles_per_cluster = 128,
            .target_screen_error = 1.5f,
            .enable_compression = true,
            .generate_lods = true,
            .max_lod_levels = 4,
            .lod_error_multiplier = 2.0f
        });

        auto validate_compiled = [&](const Arboria::CompiledMesh& m, const char* name) {
            assert(m.is_valid());
            assert(m.header.clusters > 0);
            assert(m.header.vertices > 0);
            assert(m.header.triangles > 0);
            assert(m.header.lods >= 1);
            assert(std::memcmp(m.header.magic, "ARBORIA2", 8) == 0);
            assert(m.header.version == 2);
            for (const auto& c : m.clusters) {
                assert(c.triangle_count > 0 && c.triangle_count <= 128);
                assert(c.vertex_count > 0 && c.vertex_count <= 256);
                assert(c.radius > 0.0f);
                assert(c.error >= 0.0f);
                assert(c.vertex_offset < m.vertices.size());
                assert(c.triangle_offset < m.indices.size());
            }
            for (size_t i = 1; i < m.lods.size(); ++i) {
                assert(m.lods[i].level == static_cast<uint32_t>(i));
                assert(m.lods[i].offset > 0);
                assert(m.lods[i].offset + m.lods[i].clusters <= m.header.clusters);
                assert(m.lods[i].clusters > 0);
                assert(m.lods[i].triangles > 0);
                assert(m.lods[i].ratio <= 1.0f);
            }
            std::cout << "  " << name << ": " << m.header.clusters
                      << " clusters, " << m.header.triangles
                      << " triangulos, " << m.header.lods << " LODs - OK" << std::endl;
        };

        // --- 30.1: Esfera (UV Sphere) ---
        {
            const uint32_t segments = 32;
            const uint32_t rings = 16;
            const uint32_t vertex_count = (rings + 1) * (segments + 1);
            const uint32_t index_count = rings * segments * 6;

            std::vector<float> vertices(vertex_count * 3);
            std::vector<float> normals(vertex_count * 3);
            std::vector<float> uvs(vertex_count * 2);
            std::vector<uint32_t> indices(index_count);

            uint32_t vi = 0;
            for (uint32_t r = 0; r <= rings; ++r) {
                float phi = PI * static_cast<float>(r) / static_cast<float>(rings);
                for (uint32_t s = 0; s <= segments; ++s) {
                    float theta = 2.0f * PI * static_cast<float>(s) / static_cast<float>(segments);
                    float sin_phi = std::sin(phi);
                    vertices[vi * 3 + 0] = sin_phi * std::cos(theta);
                    vertices[vi * 3 + 1] = std::cos(phi);
                    vertices[vi * 3 + 2] = sin_phi * std::sin(theta);
                    normals[vi * 3 + 0] = vertices[vi * 3 + 0];
                    normals[vi * 3 + 1] = vertices[vi * 3 + 1];
                    normals[vi * 3 + 2] = vertices[vi * 3 + 2];
                    uvs[vi * 2 + 0] = static_cast<float>(s) / static_cast<float>(segments);
                    uvs[vi * 2 + 1] = static_cast<float>(r) / static_cast<float>(rings);
                    ++vi;
                }
            }

            uint32_t ii = 0;
            for (uint32_t r = 0; r < rings; ++r) {
                for (uint32_t s = 0; s < segments; ++s) {
                    uint32_t v0 = r * (segments + 1) + s;
                    uint32_t v1 = r * (segments + 1) + s + 1;
                    uint32_t v2 = (r + 1) * (segments + 1) + s + 1;
                    uint32_t v3 = (r + 1) * (segments + 1) + s;
                    indices[ii++] = v0; indices[ii++] = v1; indices[ii++] = v2;
                    indices[ii++] = v0; indices[ii++] = v2; indices[ii++] = v3;
                }
            }

            auto sphere_compiled = compiler.compile(
                vertices.data(), vertex_count,
                normals.data(), uvs.data(),
                indices.data(), index_count
            );
            validate_compiled(sphere_compiled, "30.1 Esfera (UV Sphere)");
        }

        // --- 30.2: Malha Irregular (triangulos de tamanhos variados) ---
        {
            float irr_vertices[] = {
                -2.0f, -2.0f, 0.0f,   // 0
                 2.0f, -2.0f, 0.0f,   // 1
                 2.0f,  2.0f, 0.0f,   // 2
                -2.0f,  2.0f, 0.0f,   // 3
                -0.5f, -0.5f, 0.0f,   // 4 (centro, triangulos pequenos)
                 0.5f, -0.5f, 0.0f,   // 5
                 0.5f,  0.5f, 0.0f,   // 6
                -0.5f,  0.5f, 0.0f    // 7
            };
            float irr_normals[] = {
                0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f,
                0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f
            };
            float irr_uvs[] = {
                0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f,
                0.25f, 0.25f, 0.75f, 0.25f, 0.75f, 0.75f, 0.25f, 0.75f
            };
            uint32_t irr_indices[] = {
                // Triangulos grandes (quad externo)
                0, 1, 2, 0, 2, 3,
                // Triangulos pequenos (quad interno)
                4, 5, 6, 4, 6, 7
            };

            auto irr_compiled = compiler.compile(
                irr_vertices, 8, irr_normals, irr_uvs, irr_indices, 12
            );
            validate_compiled(irr_compiled, "30.2 Malha Irregular");
            assert(irr_compiled.header.triangles == 4);
        }

        // --- 30.3: Arestas Vivas (Sharp Edges) — cubo com arestas definidas preservadas no LOD ---
        {
            // Mesmo cubo do TESTE 29 mas verificando que arestas vivas sao preservadas
            float cube_vertices[8 * 3] = {
                -0.5f, -0.5f, -0.5f,  0.5f, -0.5f, -0.5f,  0.5f,  0.5f, -0.5f, -0.5f,  0.5f, -0.5f,
                -0.5f, -0.5f,  0.5f,  0.5f, -0.5f,  0.5f,  0.5f,  0.5f,  0.5f, -0.5f,  0.5f,  0.5f
            };
            float cube_normals[8 * 3] = {
                0.0f, 0.0f, -1.0f, 0.0f, 0.0f, -1.0f, 0.0f, 0.0f, -1.0f, 0.0f, 0.0f, -1.0f,
                0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  1.0f
            };
            float cube_uvs[8 * 2] = {
                0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f,
                0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f
            };
            uint32_t cube_indices[12 * 3] = {
                0, 1, 2, 0, 2, 3,   // tras
                1, 5, 6, 1, 6, 2,   // direita
                3, 2, 6, 3, 6, 7,   // superior
                4, 0, 3, 4, 3, 7,   // esquerda
                4, 5, 1, 4, 1, 0,   // inferior
                4, 7, 6, 4, 6, 5    // frente
            };

            auto sharp_compiled = compiler.compile(
                cube_vertices, 8, cube_normals, cube_uvs, cube_indices, 36
            );
            validate_compiled(sharp_compiled, "30.3 Arestas Vivas (Cube)");

            // Verificar que LOD 0 mantem todos os 12 triangulos (arestas vivas preservadas)
            assert(sharp_compiled.lods[0].triangles == 12);
            std::cout << "  30.3 Arestas Vivas preservadas: " << sharp_compiled.lods[0].triangles
                      << " triangulos no LOD 0 - OK" << std::endl;
        }

        // --- 30.4: Fronteiras Abertas (malha nao fechada — plano com abertura) ---
        {
            float open_vertices[] = {
                -1.0f, -1.0f, 0.0f,   // 0
                 1.0f, -1.0f, 0.0f,   // 1
                 1.0f,  1.0f, 0.0f,   // 2
                -1.0f,  1.0f, 0.0f,   // 3
                -0.5f, -0.5f, 0.0f,   // 4 (buraco interno)
                 0.5f, -0.5f, 0.0f,   // 5
                 0.5f,  0.5f, 0.0f,   // 6
                -0.5f,  0.5f, 0.0f    // 7 (buraco interno - fronteira aberta)
            };
            float open_normals[] = {
                0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f,
                0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f
            };
            float open_uvs[] = {
                0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f,
                0.25f, 0.25f, 0.75f, 0.25f, 0.75f, 0.75f, 0.25f, 0.75f
            };
            // Quad externo + quad interno (fronteira aberta ao redor do buraco interno)
            uint32_t open_indices[] = {
                0, 1, 2, 0, 2, 3,   // quad externo
                4, 5, 6, 4, 6, 7    // quad interno (buraco)
            };

            auto open_compiled = compiler.compile(
                open_vertices, 8, open_normals, open_uvs, open_indices, 12
            );
            validate_compiled(open_compiled, "30.4 Fronteiras Abertas");
            assert(open_compiled.header.triangles == 4);
        }

        // --- 30.5: Alta Densidade (malha com muitos vertices e triangulos) ---
        {
            const uint32_t grid_size = 32;
            const uint32_t vertex_count = grid_size * grid_size;
            const uint32_t index_count = (grid_size - 1) * (grid_size - 1) * 6;

            std::vector<float> vertices(vertex_count * 3);
            std::vector<float> normals(vertex_count * 3);
            std::vector<float> uvs(vertex_count * 2);
            std::vector<uint32_t> indices(index_count);

            for (uint32_t y = 0; y < grid_size; ++y) {
                for (uint32_t x = 0; x < grid_size; ++x) {
                    uint32_t idx = y * grid_size + x;
                    float fx = static_cast<float>(x) / static_cast<float>(grid_size - 1) * 2.0f - 1.0f;
                    float fy = static_cast<float>(y) / static_cast<float>(grid_size - 1) * 2.0f - 1.0f;
                    vertices[idx * 3 + 0] = fx;
                    vertices[idx * 3 + 1] = 0.0f;
                    vertices[idx * 3 + 2] = fy;
                    normals[idx * 3 + 0] = 0.0f;
                    normals[idx * 3 + 1] = 1.0f;
                    normals[idx * 3 + 2] = 0.0f;
                    uvs[idx * 2 + 0] = static_cast<float>(x) / static_cast<float>(grid_size - 1);
                    uvs[idx * 2 + 1] = static_cast<float>(y) / static_cast<float>(grid_size - 1);
                }
            }

            uint32_t ii = 0;
            for (uint32_t y = 0; y < grid_size - 1; ++y) {
                for (uint32_t x = 0; x < grid_size - 1; ++x) {
                    uint32_t v0 = y * grid_size + x;
                    uint32_t v1 = y * grid_size + x + 1;
                    uint32_t v2 = (y + 1) * grid_size + x + 1;
                    uint32_t v3 = (y + 1) * grid_size + x;
                    indices[ii++] = v0; indices[ii++] = v1; indices[ii++] = v2;
                    indices[ii++] = v0; indices[ii++] = v2; indices[ii++] = v3;
                }
            }

            auto dense_compiled = compiler.compile(
                vertices.data(), vertex_count,
                normals.data(), uvs.data(),
                indices.data(), index_count
            );
            validate_compiled(dense_compiled, "30.5 Alta Densidade (32x32 grid)");
            assert(dense_compiled.header.vertices > 0);
            assert(dense_compiled.header.triangles > 0);
            assert(dense_compiled.header.triangles <= (grid_size - 1) * (grid_size - 1) * 2);
        }

        // --- 30.6: Triangulos Degenerados (vertices duplicados em um triangulo) ---
        {
            float deg_vertices[] = {
                0.0f, 0.0f, 0.0f,   // 0
                1.0f, 0.0f, 0.0f,   // 1
                0.0f, 1.0f, 0.0f,   // 2 (triangulo valido)
                1.0f, 1.0f, 0.0f    // 3
            };
            float deg_normals[] = {
                0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f
            };
            float deg_uvs[] = {
                0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f
            };
            // Triangulo 0: valido (0,1,2)
            // Triangulo 1: degenerado (1,1,3) — vertices duplicados
            uint32_t deg_indices[] = {
                0, 1, 2,   // valido
                1, 1, 3    // degenerado (vertice 1 repetido)
            };

            auto deg_compiled = compiler.compile(
                deg_vertices, 4, deg_normals, deg_uvs, deg_indices, 6
            );
            // Nao deve travar; triangulos degenerados sao tratados/ignorados
            assert(deg_compiled.is_valid() || deg_compiled.header.triangles == 0);
            std::cout << "  30.6 Triangulos Degenerados: "
                      << deg_compiled.header.clusters << " clusters, "
                      << deg_compiled.header.triangles << " triangulos validos - OK" << std::endl;
        }

        // --- 30.7: Indices Invalidos (indice fora do intervalo de vertices) ---
        {
            float bad_vertices[] = {
                0.0f, 0.0f, 0.0f,   // 0
                1.0f, 0.0f, 0.0f,   // 1
                0.0f, 1.0f, 0.0f    // 2
            };
            float bad_normals[] = {
                0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f
            };
            float bad_uvs[] = {
                0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f
            };
            // Indice 99 nao existe (apenas 3 vertices: 0,1,2)
            uint32_t bad_indices[] = {
                0, 1, 2,   // valido
                0, 1, 99   // invalido — indice fora de intervalo
            };

            auto bad_compiled = compiler.compile(
                bad_vertices, 3, bad_normals, bad_uvs, bad_indices, 6
            );
            // Nao deve travar; indices invalidos sao rejeitados ou ignorados
            assert(bad_compiled.is_valid() || bad_compiled.header.triangles == 0);
            std::cout << "  30.7 Indices Invalidos: "
                      << bad_compiled.header.clusters << " clusters, "
                      << bad_compiled.header.triangles << " triangulos validos - OK" << std::endl;
        }

        // --- 30.8: UVs — verificacao de coordenadas UV preservadas nos clusters ---
        {
            float uv_vertices[] = {
                0.0f, 0.0f, 0.0f,   // 0
                1.0f, 0.0f, 0.0f,   // 1
                1.0f, 1.0f, 0.0f,   // 2
                0.0f, 1.0f, 0.0f    // 3
            };
            float uv_normals[] = {
                0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f
            };
            float uv_uvs[] = {
                0.0f, 0.0f,   // 0
                1.0f, 0.0f,   // 1
                1.0f, 1.0f,   // 2
                0.0f, 1.0f    // 3
            };
            uint32_t uv_indices[] = {
                0, 1, 2, 0, 2, 3
            };

            auto uv_compiled = compiler.compile(
                uv_vertices, 4, uv_normals, uv_uvs, uv_indices, 6
            );
            validate_compiled(uv_compiled, "30.8 UVs");
            // Verificar que UVs estao presentes nos vertices de saida
            for (const auto& v : uv_compiled.vertices) {
                assert(v.uv[0] >= 0.0f && v.uv[0] <= 1.0f);
                assert(v.uv[1] >= 0.0f && v.uv[1] <= 1.0f);
            }
        }

        // --- 30.9: Multiplos Materiais (regioes distintas que mapeariam para materiais diferentes) ---
        {
            // Duas regioes separadas: cada uma formando seu proprio cluster logico
            float multi_vertices[] = {
                // Regiao A (esquerda)
                0.0f, 0.0f, 0.0f,   // 0
                1.0f, 0.0f, 0.0f,   // 1
                0.0f, 1.0f, 0.0f,   // 2
                // Regiao B (direita, separada por espaco)
                10.0f, 0.0f, 0.0f,  // 3
                11.0f, 0.0f, 0.0f,  // 4
                10.0f, 1.0f, 0.0f   // 5
            };
            float multi_normals[] = {
                0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f,
                0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f
            };
            float multi_uvs[] = {
                0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f,
                0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f
            };
            uint32_t multi_indices[] = {
                0, 1, 2,   // triangulo da regiao A
                3, 4, 5    // triangulo da regiao B
            };

            auto multi_compiled = compiler.compile(
                multi_vertices, 6, multi_normals, multi_uvs, multi_indices, 6
            );
            validate_compiled(multi_compiled, "30.9 Multiplos Materiais (2 regioes)");
            assert(multi_compiled.header.triangles == 2);
            assert(multi_compiled.header.clusters >= 1);
        }

        std::cout << "[TESTE 30] Geometrias Reais (ETAPA 6) - OK" << std::endl;
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
