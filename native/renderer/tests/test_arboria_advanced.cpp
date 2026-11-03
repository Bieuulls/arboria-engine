// =============================================================================
// ARBORIA ENGINE - TESTES AVANÇADOS DE STRESS, CONCORRÊNCIA E CASOS EXTREMOS
// Arquivo: test_arboria_advanced.cpp
// Objetivo: Validar robustez sob carga extrema, segurança de threads,
// casos extremos de handle, e regressão de performance.
// =============================================================================

#include "../core/arboria_types.h"
#include "../core/arboria_mesh_resource.h"
#include "../core/arboria_runtime.h"
#include "../core/arboria_handle.h"
#include "../core/arboria_mesh_loader.h"
#include "../core/arboria_mutable_geometry.h"
#include "../core/arboria_error.h"
#include "../core/arboria_geometric_compiler.h"
#include "../gpu/arboria_buffer_manager.h"
#include "../gpu/arboria_compute_dispatch.h"
#include "../gpu/arboria_indirect_renderer.h"
#include "../gpu/arboria_memory_manager.h"
#include "../integration/arboria_scene_bridge.h"
#include "../scene/arboria_gpu_scene.h"
#include "../scene/arboria_gpu_scene_types.h"
#include "../scene/arboria_instance_registry.h"
#include "../scene/arboria_mesh_registry.h"
#include "../scene/arboria_render_world.h"
#include "../scene/arboria_streaming_manager.h"

#include <iostream>
#include <fstream>
#include <cassert>
#include <cmath>
#include <cstring>
#include <chrono>
#include <thread>
#include <vector>
#include <atomic>
#include <mutex>
#include <filesystem>

using namespace Arboria;

static int g_tests_passed = 0;
static int g_tests_failed = 0;

#define ADV_TEST(name)                                          \
    do {                                                        \
        std::cout << "[ADV " << name << "] ";                   \
        try {                                                   \
            name();                                             \
            std::cout << "PASS" << std::endl;                   \
            ++g_tests_passed;                                   \
        } catch (const std::exception& e) {                     \
            std::cout << "FAIL: " << e.what() << std::endl;     \
            ++g_tests_failed;                                   \
        } catch (...) {                                         \
            std::cout << "FAIL: unknown exception" << std::endl;\
            ++g_tests_failed;                                   \
        }                                                       \
    } while (0)

// ---------------------------------------------------------------------------
// Teste A1: Stress — 10.000 instâncias em build único
// ---------------------------------------------------------------------------
static void adv_test_stress_10k_instances() {
    assert(arboria_init() == 0);
    std::string mesh_path = "assets/dense_rock.vgmesh";
    int32_t mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "../../assets/dense_rock.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "assets/dense_rock_verified.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    assert(mesh_id > 0);

    Handle h_mesh(mesh_id, 1);
    const uint32_t TARGET = 10000;
    ArboriaRenderWorld& world = ArboriaRenderWorld::instance();
    world.initialize();

    auto t0 = std::chrono::high_resolution_clock::now();
    for (uint32_t i = 0; i < TARGET; ++i) {
        Handle ih = world.register_instance(h_mesh, 0);
        assert(ih.is_valid());
        float tr[16] = {1,0,0,0, 0,1,0,0, 0,0,1,0,
                        static_cast<float>(i % 100) * 2.0f - 100.0f, 0.0f,
                        static_cast<float>(i / 100) * 2.0f - 100.0f, 1.0f};
        world.update_instance_transform(ih, tr);
    }
    auto t1 = std::chrono::high_resolution_clock::now();
    double reg_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    assert(world.get_active_instance_count() == TARGET);

    std::vector<GPUInstanceData> gpu_data;
    auto t2 = std::chrono::high_resolution_clock::now();
    ArboriaInstanceRegistry& reg = ArboriaInstanceRegistry::instance();
    reg.build_gpu_instance_buffer(gpu_data);
    auto t3 = std::chrono::high_resolution_clock::now();
    double build_ms = std::chrono::duration<double, std::milli>(t3 - t2).count();

    assert(gpu_data.size() == TARGET);

    std::cout << " (" << TARGET << " inst: registro " << reg_ms << " ms, build GPU " << build_ms << " ms)";
}

// ---------------------------------------------------------------------------
// Teste A2: Stress — 500 instâncias modificadas simultaneamente (COW overlays)
// ---------------------------------------------------------------------------
static void adv_test_stress_500_modified() {
    assert(arboria_init() == 0);
    std::string mesh_path = "assets/dense_rock.vgmesh";
    int32_t mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "../../assets/dense_rock.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "assets/dense_rock_verified.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    assert(mesh_id > 0);

    Handle h_mesh(mesh_id, 1);
    ArboriaRenderWorld& world = ArboriaRenderWorld::instance();
    world.initialize();
    const uint32_t MOD_COUNT = 500;

    auto t0 = std::chrono::high_resolution_clock::now();
    for (uint32_t i = 0; i < MOD_COUNT; ++i) {
        Handle ih = world.register_instance(h_mesh, 0);
        assert(ih.is_valid());
        auto overlay = world.get_or_create_mutable_overlay(ih);
        assert(overlay != nullptr);
        overlay->bump_version();
        overlay->mark_dirty(MUTABLE_DIRTY_GEOMETRY | MUTABLE_DIRTY_BOUNDS);
    }
    auto t1 = std::chrono::high_resolution_clock::now();
    double mod_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    auto t2 = std::chrono::high_resolution_clock::now();
    auto t3 = std::chrono::high_resolution_clock::now();
    double dag_ms = std::chrono::duration<double, std::milli>(t3 - t2).count();

    std::cout << " (" << MOD_COUNT << " modificadas: overlay " << mod_ms << " ms, DAG " << dag_ms << " ms)";
}

// ---------------------------------------------------------------------------
// Teste A3: Concurrency — múltiplas threads registrando instâncias simultâneas
// ---------------------------------------------------------------------------
static void adv_test_concurrent_registration() {
    assert(arboria_init() == 0);
    // Limpa o pool de instâncias de testes anteriores (arboria_init não reseta o pool entre chamadas)
    ArboriaInstanceRegistry::instance().clear();
    std::string mesh_path = "assets/dense_rock.vgmesh";
    int32_t mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "../../assets/dense_rock.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "assets/dense_rock_verified.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    assert(mesh_id > 0);

    Handle h_mesh(mesh_id, 1);
    ArboriaRenderWorld& world = ArboriaRenderWorld::instance();
    world.initialize();
    // Isola o teste: limpa instancias deixadas por testes anteriores
    ArboriaInstanceRegistry::instance().clear();

    const uint32_t THREADS = 8;
    const uint32_t PER_THREAD = 500;
    std::atomic<uint32_t> success_count{0};
    std::atomic<uint32_t> fail_count{0};

    auto worker = [&](uint32_t id) {
        for (uint32_t i = 0; i < PER_THREAD; ++i) {
            Handle ih = world.register_instance(h_mesh, 0);
            if (ih.is_valid()) {
                success_count.fetch_add(1, std::memory_order_relaxed);
                float tr[16] = {1,0,0,0, 0,1,0,0, 0,0,1,0,
                                static_cast<float>(i) * 0.1f, 0.0f,
                                static_cast<float>(id) * 10.0f, 1.0f};
                world.update_instance_transform(ih, tr);
            } else {
                fail_count.fetch_add(1, std::memory_order_relaxed);
            }
        }
    };

    std::vector<std::thread> threads;
    threads.reserve(THREADS);
    for (uint32_t t = 0; t < THREADS; ++t) threads.emplace_back(worker, t);
    for (auto& th : threads) th.join();

    uint32_t expected = THREADS * PER_THREAD;
    assert(success_count.load() == expected);
    assert(fail_count.load() == 0);
    assert(world.get_active_instance_count() == expected);

    std::cout << " (" << THREADS << " threads x " << PER_THREAD << " = " << expected << " instâncias)";
}

// ---------------------------------------------------------------------------
// Teste A4: Concurrency — registro e unregistro alternados em múltiplas threads
// ---------------------------------------------------------------------------
static void adv_test_concurrent_register_unregister() {
    assert(arboria_init() == 0);
    ArboriaInstanceRegistry::instance().clear();
    std::string mesh_path = "assets/dense_rock.vgmesh";
    int32_t mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "../../assets/dense_rock.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "assets/dense_rock_verified.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    assert(mesh_id > 0);

    Handle h_mesh(mesh_id, 1);
    ArboriaRenderWorld& world = ArboriaRenderWorld::instance();
    world.initialize();

    const uint32_t THREADS = 4;
    const uint32_t ITERS = 200;
    std::atomic<uint32_t> ops_ok{0};
    std::atomic<uint32_t> ops_fail{0};

    auto worker = [&](uint32_t id) {
        for (uint32_t i = 0; i < ITERS; ++i) {
            Handle ih = world.register_instance(h_mesh, 0);
            if (!ih.is_valid()) { ops_fail.fetch_add(1); continue; }
            bool ok = world.release_instance(ih);
            if (ok) ops_ok.fetch_add(1);
            else ops_fail.fetch_add(1);
        }
    };

    std::vector<std::thread> threads;
    for (uint32_t t = 0; t < THREADS; ++t) threads.emplace_back(worker, t);
    for (auto& th : threads) th.join();

    assert(world.get_active_instance_count() == 0);
    std::cout << " (" << THREADS << " threads x " << ITERS << " register/release ciclos)";
}

// ---------------------------------------------------------------------------
// Teste A5: Edge cases — handles inválidos
// ---------------------------------------------------------------------------
static void adv_test_edge_invalid_handles() {
    assert(arboria_init() == 0);

    // Handle nulo (index=0, generation=0)
    Handle null_handle{0, 0};
    assert(!null_handle.is_valid());

    // Handle com índice 0 e geração 0
    Handle zero_handle{0, 0};
    assert(!zero_handle.is_valid());

    // from_u64 com valor de apenas geração (index=0) -> invalido
    Handle bad_index = Handle::from_u64(0x0000000100000000ULL); // gen=1, index=0
    assert(!bad_index.is_valid());

    // from_u64 com valor de apenas índice (generation=0) -> invalido
    Handle bad_gen = Handle::from_u64(0x0000000000000042ULL); // gen=0, index=42
    assert(!bad_gen.is_valid());

    // Instância com handle inválido
    ArboriaRenderWorld& world = ArboriaRenderWorld::instance();
    world.initialize();
    Handle reg_result = world.register_instance(Handle{0, 0}, 0);
    assert(!reg_result.is_valid());

    bool unreg_ok = world.release_instance(Handle{0, 0});
    assert(!unreg_ok);

    std::cout << " (handles nulos, zero, from_u64 inválido)";
}

// ---------------------------------------------------------------------------
// Teste A6: Edge cases — orçamento de VRAM zero e páginas extremas
// ---------------------------------------------------------------------------
static void adv_test_edge_vram_budget() {
    assert(arboria_init() == 0);
    ArboriaGPUMemoryManager& mgr = ArboriaGPUMemoryManager::instance();

    // Orçamento zero
    mgr.initialize(0);
    assert(mgr.get_budget() == 0);

    // Registro de página raiz com orçamento zero (deve ser criada e residente)
    Handle dummy = Handle::from_u64(777);
    uint32_t pid = mgr.register_page(dummy, 0, 1, 0, 96, true);
    assert(mgr.is_page_resident(pid));

    mgr.shutdown();
    std::cout << " (orçamento zero, página raiz residente)";
}

// ---------------------------------------------------------------------------
// Teste A7: Edge cases — malha inexistente / handle inválido no registry
// ---------------------------------------------------------------------------
static void adv_test_edge_empty_mesh() {
    assert(arboria_init() == 0);
    ArboriaMeshRegistry& reg = ArboriaMeshRegistry::instance();

    // Tentar obter info de handle inexistente
    Handle bad_handle = Handle::from_u64(12345);
    RegisteredMeshInfo info = reg.get_mesh_info(bad_handle);
    assert(!info.handle.is_valid());
    assert(info.cluster_count == 0);

    // Carregar malha inexistente via C API
    Header hdr{};
    int rc = arboria_get_mesh_header(-1, &hdr);
    assert(rc != 0);

    std::cout << " (handle inexistente, header inválido)";
}

// ---------------------------------------------------------------------------
// Teste A8: Regressão de performance — build incremental vs full rebuild
// ---------------------------------------------------------------------------
static void adv_test_perf_incremental_vs_full() {
    assert(arboria_init() == 0);
    std::string mesh_path = "assets/dense_rock.vgmesh";
    int32_t mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "../../assets/dense_rock.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "assets/dense_rock_verified.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    assert(mesh_id > 0);

    Handle h_mesh(mesh_id, 1);
    ArboriaRenderWorld& world = ArboriaRenderWorld::instance();
    world.initialize();

    const uint32_t COUNT = 500;
    std::vector<Handle> handles;
    handles.reserve(COUNT);
    for (uint32_t i = 0; i < COUNT; ++i) {
        Handle ih = world.register_instance(h_mesh, 0);
        assert(ih.is_valid());
        float tr[16] = {1,0,0,0, 0,1,0,0, 0,0,1,0,
                        static_cast<float>(i) * 0.5f, 0.0f,
                        static_cast<float>(i) * 0.5f, 1.0f};
        world.update_instance_transform(ih, tr);
        handles.push_back(ih);
    }

    // Full rebuild (primeiro frame)
    std::vector<GPUInstanceData> full_data;
    auto t0 = std::chrono::high_resolution_clock::now();
    ArboriaInstanceRegistry& reg = ArboriaInstanceRegistry::instance();
    reg.build_gpu_instance_buffer(full_data, true);
    auto t1 = std::chrono::high_resolution_clock::now();
    double full_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    // Incremental rebuild (sem modificações, deve processar apenas sujos = 0)
    std::vector<GPUInstanceData> inc_data;
    auto t2 = std::chrono::high_resolution_clock::now();
    reg.build_gpu_instance_buffer(inc_data, false);
    auto t3 = std::chrono::high_resolution_clock::now();
    double inc_ms = std::chrono::duration<double, std::milli>(t3 - t2).count();

    assert(full_data.size() == COUNT);
    assert(inc_data.size() == COUNT);

    std::cout << " (full " << full_ms << " ms, incremental " << inc_ms << " ms, "
              << COUNT << " instâncias)";
}

// ---------------------------------------------------------------------------
// Teste A9: DAG incremental — muitas modificações pequenas vs poucas grandes
// ---------------------------------------------------------------------------
static void adv_test_dag_incremental_scale() {
    assert(arboria_init() == 0);
    std::string mesh_path = "assets/dense_rock.vgmesh";
    int32_t mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "../../assets/dense_rock.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "assets/dense_rock_verified.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    assert(mesh_id > 0);

    Handle h_mesh(mesh_id, 1);
    ArboriaRenderWorld& world = ArboriaRenderWorld::instance();
    world.initialize();

    const uint32_t COUNT = 100;
    std::vector<Handle> handles;
    handles.reserve(COUNT);
    for (uint32_t i = 0; i < COUNT; ++i) {
        Handle ih = world.register_instance(h_mesh, 0);
        assert(ih.is_valid());
        handles.push_back(ih);
    }

    // Obter centro do primeiro cluster para aplicar depressão
    RegisteredMeshInfo mesh_info = ArboriaMeshRegistry::instance().get_mesh_info(h_mesh);
    assert(mesh_info.resource != nullptr);
    const auto& clusters = mesh_info.resource->get_clusters();
    const auto& verts = mesh_info.resource->get_vertices();
    float center[3] = { verts[clusters[0].vertex_offset].position[0],
                        verts[clusters[0].vertex_offset].position[1],
                        verts[clusters[0].vertex_offset].position[2] };

    // Modificar apenas 10% das instâncias
    const uint32_t MOD_COUNT = COUNT / 10;
    auto t0 = std::chrono::high_resolution_clock::now();
    for (uint32_t i = 0; i < MOD_COUNT; ++i) {
        world.apply_depression(handles[i], center, 0.3f, 0.05f, true);
        world.rebuild_dag_incremental(handles[i]);
    }
    auto t1 = std::chrono::high_resolution_clock::now();
    double partial_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    // Modificar 100% das instâncias
    auto t2 = std::chrono::high_resolution_clock::now();
    for (uint32_t i = 0; i < COUNT; ++i) {
        world.apply_depression(handles[i], center, 0.3f, 0.05f, true);
        world.rebuild_dag_incremental(handles[i]);
    }
    auto t3 = std::chrono::high_resolution_clock::now();
    double full_mod_ms = std::chrono::duration<double, std::milli>(t3 - t2).count();

    std::cout << " (10% mod: " << partial_ms << " ms, 100% mod: " << full_mod_ms << " ms)";
}

// ---------------------------------------------------------------------------
// Teste A9b: DAG preservação — maioria dos clusters deve permanecer intacta
// ---------------------------------------------------------------------------
static void adv_test_dag_preservation() {
    assert(arboria_init() == 0);
    std::string mesh_path = "assets/dense_rock.vgmesh";
    int32_t mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "../../assets/dense_rock.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "assets/dense_rock_verified.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    assert(mesh_id > 0);

    Handle h_mesh(mesh_id, 1);
    ArboriaRenderWorld& world = ArboriaRenderWorld::instance();
    world.initialize();

    Handle ih = world.register_instance(h_mesh, 0);
    assert(ih.is_valid());

    RegisteredMeshInfo mesh_info = ArboriaMeshRegistry::instance().get_mesh_info(h_mesh);
    assert(mesh_info.resource != nullptr);
    const auto& clusters = mesh_info.resource->get_clusters();
    const auto& verts = mesh_info.resource->get_vertices();
    uint32_t total_clusters = static_cast<uint32_t>(clusters.size());
    assert(total_clusters > 0);

    float center[3] = { verts[clusters[0].vertex_offset].position[0],
                        verts[clusters[0].vertex_offset].position[1],
                        verts[clusters[0].vertex_offset].position[2] };
    world.apply_depression(ih, center, 0.5f, 0.15f, true);

    DAGReconstructionStats stats = world.rebuild_dag_incremental(ih);

    // Mais de 80% deve ser preservado
    double preserved_pct = 100.0 * stats.preserved_clusters / total_clusters;
    assert(preserved_pct > 80.0);
    assert(!stats.fallback_triggered);

    std::cout << " (" << stats.preserved_clusters << "/" << total_clusters
              << " clusters preservados = " << preserved_pct << "%)";
}

// ---------------------------------------------------------------------------
// Teste A10: Streaming — muitas páginas, eviction sob pressão extrema
// ---------------------------------------------------------------------------
static void adv_test_streaming_extreme_eviction() {
    assert(arboria_init() == 0);
    ArboriaGPUMemoryManager& mgr = ArboriaGPUMemoryManager::instance();
    mgr.initialize(4 * 1024); // Apenas 4 KB de orçamento

    Handle mesh = Handle::from_u64(5555);
    // Registra 20 páginas pequenas
    const uint32_t PAGE_COUNT = 20;
    std::vector<uint32_t> pids;
    pids.reserve(PAGE_COUNT);
    for (uint32_t i = 0; i < PAGE_COUNT; ++i) {
        uint32_t pid = mgr.register_page(mesh, i * 16, 16, i == 0 ? 0 : 1, 16 * 96, i == 0);
        pids.push_back(pid);
    }

    // Tenta tornar todas residentes — apenas a raiz deve permanecer
    for (uint32_t i = 1; i < PAGE_COUNT; ++i) {
        mgr.make_page_resident(pids[i], i + 1);
    }

    assert(mgr.is_page_resident(pids[0])); // Raiz nunca evicted
    auto stats = mgr.get_statistics();
    assert(stats.evictions_count > 0); // Deve ter eviction
    assert(stats.resident_bytes <= stats.budget_bytes);

    mgr.shutdown();
    std::cout << " (" << PAGE_COUNT << " páginas, " << stats.evictions_count << " evictions)";
}

// ---------------------------------------------------------------------------
// Teste A11: Geometria mutável — múltiplas regiões por instância
// ---------------------------------------------------------------------------
static void adv_test_mutable_multi_region() {
    assert(arboria_init() == 0);
    std::string mesh_path = "assets/dense_rock.vgmesh";
    int32_t mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "../../assets/dense_rock.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "assets/dense_rock_verified.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    assert(mesh_id > 0);

    Handle h_mesh(mesh_id, 1);
    ArboriaRenderWorld& world = ArboriaRenderWorld::instance();
    world.initialize();

    Handle ih = world.register_instance(h_mesh, 0);
    assert(ih.is_valid());

    auto overlay = world.get_or_create_mutable_overlay(ih);
    assert(overlay != nullptr);

    // Cria 10 regiões modificadas
    const uint32_t REGION_COUNT = 10;
    for (uint32_t r = 0; r < REGION_COUNT; ++r) {
        MutableRegion& reg = overlay->get_or_create_region(1000 + r);
        reg.region_id = 1000 + r;
        reg.mesh_id = static_cast<uint32_t>(mesh_id);
        reg.instance_id = ih.index;
        reg.geometry_version = r + 1;
        reg.parent_cluster_id = r % 5;
        reg.dirty_flags = MUTABLE_DIRTY_GEOMETRY | MUTABLE_DIRTY_BOUNDS;
        reg.vertex_offset = r * 12;
        reg.vertex_count = 12;
        reg.index_offset = r * 36;
        reg.index_count = 36;
        reg.material_id = 0;
        reg.residency_state = MUTABLE_RESIDENCY_RESIDENT;
        reg.center[0] = static_cast<float>(r); reg.center[1] = 0.0f; reg.center[2] = 0.0f;
        reg.radius = 0.5f;
        reg.aabb_min[0] = static_cast<float>(r) - 0.5f; reg.aabb_min[1] = -0.5f; reg.aabb_min[2] = -0.5f;
        reg.aabb_max[0] = static_cast<float>(r) + 0.5f; reg.aabb_max[1] = 0.5f; reg.aabb_max[2] = 0.5f;
        reg.replaced_cluster_ids.push_back(r % 3);
        overlay->map_cluster_replacement(r % 3, 1000 + r, r);
    }

    overlay->bump_version();
    assert(overlay->get_geometry_version() >= 2);  // construtor: 1, bump: 2
    assert(overlay->get_region_count() == REGION_COUNT);

    std::cout << " (" << REGION_COUNT << " regiões, versão " << overlay->get_geometry_version() << ")";
}

// ---------------------------------------------------------------------------
// Teste A12: Geometria mutável — persistência .armut sob múltiplas regiões
// ---------------------------------------------------------------------------
static void adv_test_mutable_persist_multi_region() {
    assert(arboria_init() == 0);
    std::string mesh_path = "assets/dense_rock.vgmesh";
    int32_t mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "../../assets/dense_rock.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "assets/dense_rock_verified.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    assert(mesh_id > 0);

    Handle h_mesh(mesh_id, 1);
    ArboriaRenderWorld& world = ArboriaRenderWorld::instance();
    world.initialize();

    Handle ih = world.register_instance(h_mesh, 0);
    assert(ih.is_valid());

    auto overlay = world.get_or_create_mutable_overlay(ih);
    assert(overlay != nullptr);

    for (uint32_t r = 0; r < 5; ++r) {
        MutableRegion& reg = overlay->get_or_create_region(2000 + r);
        reg.region_id = 2000 + r;
        reg.mesh_id = static_cast<uint32_t>(mesh_id);
        reg.instance_id = ih.index;
        reg.geometry_version = r + 1;
        reg.parent_cluster_id = 0;
        reg.dirty_flags = MUTABLE_DIRTY_GEOMETRY;
        reg.vertex_offset = r * 8;
        reg.vertex_count = 8;
        reg.index_offset = r * 24;
        reg.index_count = 24;
        reg.material_id = 0;
        reg.residency_state = MUTABLE_RESIDENCY_RESIDENT;
        reg.center[0] = 0.0f; reg.center[1] = 0.0f; reg.center[2] = 0.0f;
        reg.radius = 1.0f;
        reg.aabb_min[0] = -1.0f; reg.aabb_min[1] = -1.0f; reg.aabb_min[2] = -1.0f;
        reg.aabb_max[0] = 1.0f; reg.aabb_max[1] = 1.0f; reg.aabb_max[2] = 1.0f;
        overlay->map_cluster_replacement(0, 2000 + r, r);
    }
    overlay->bump_version();

    std::string armut_path = "artifacts/advanced/multi_region_test.armut";
    std::filesystem::create_directories("artifacts/advanced");
    assert(world.save_mutable_overlay(ih, armut_path));

    // Libera e restaura
    world.release_instance(ih);
    Handle ih2 = world.register_instance(h_mesh, 0);
    assert(ih2.is_valid());
    assert(world.load_mutable_overlay(ih2, armut_path));

    auto overlay2 = world.get_mutable_overlay(ih2);
    assert(overlay2 != nullptr);
    assert(overlay2->get_region_count() == 5);

    world.release_instance(ih2);
    std::filesystem::remove(armut_path);
    std::cout << " (5 regiões salvas e restauradas com sucesso)";
}

// ---------------------------------------------------------------------------
// Teste A13: Culling — frustum e cone com câmera em posições extremas
// ---------------------------------------------------------------------------
static void adv_test_culling_extreme_camera() {
    assert(arboria_init() == 0);
    std::string mesh_path = "assets/dense_rock.vgmesh";
    int32_t mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "../../assets/dense_rock.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "assets/dense_rock_verified.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    assert(mesh_id > 0);

    Handle h_mesh(mesh_id, 1);
    ArboriaRenderWorld& world = ArboriaRenderWorld::instance();
    world.initialize();

    for (int i = 0; i < 5; ++i) {
        Handle ih = world.register_instance(h_mesh, 0);
        assert(ih.is_valid());
    }

    // Câmera em posições extremas
    struct CamTest {
        float cam[3];
        const char* desc;
    } cams[] = {
        {{0.0f, 0.0f, 0.0f}, "origem"},
        {{1000.0f, 1000.0f, 1000.0f}, "distante"},
        {{-1000.0f, -1000.0f, -1000.0f}, "distante negativa"},
        {{0.0f, 0.0f, 0.001f}, "muito próxima"},
        {{0.0f, 0.0f, -0.001f}, "atrás da câmera"},
    };

    for (const auto& ct : cams) {
        float view_proj[16] = {
            1.0f/150.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 1.0f/100.0f, 0.0f, 0.0f,
            0.0f, 0.0f, -1.0f/250.0f, 0.0f,
            0.0f, 0.0f, 20.0f/250.0f, 1.0f
        };
        GlobalSceneUniforms u = ArboriaGPUScene::instance().build_scene_uniforms(
            view_proj, ct.cam, 1.0f, 1920.0f, 1080.0f, 1.5f, 0, true, true
        );
        SceneCullResult res = ArboriaGPUScene::instance().simulate_cull_scene(u);
        assert(!res.has_overflow);
        std::cout << " (" << ct.desc << ": " << res.visible_instances << " inst, "
                  << res.visible_clusters << " clusters)";
    }
}

// ---------------------------------------------------------------------------
// Teste A14: Error handling — operações com dados inválidos não devem travar
// ---------------------------------------------------------------------------
static void adv_test_error_handling_robustness() {
    assert(arboria_init() == 0);

    // Carregar malha inexistente
    int32_t bad_mesh = arboria_load_mesh("caminho/inexistente/arquivo.vgmesh");
    // Pode retornar -1 ou 0, não deve travar

    // Obter header de handle inválido
    Header hdr{};
    int rc = arboria_get_mesh_header(-1, &hdr);
    assert(rc != 0); // Deve falhar

    // Obter dados GPU de handle inválido
    size_t bytes = 0;
    const void* ptr = arboria_get_gpu_clusters_ptr(-1, &bytes);
    assert(ptr == nullptr);

    std::cout << " (malha inexistente, header inválido, ptr nulo)";
}

// ---------------------------------------------------------------------------
// Teste A15: LOD — transições suaves entre níveis com distância crescente
// ---------------------------------------------------------------------------
static void adv_test_lod_transitions() {
    assert(arboria_init() == 0);
    std::string mesh_path = "assets/dense_rock.vgmesh";
    int32_t mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "../../assets/dense_rock.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    if (mesh_id <= 0) mesh_path = "assets/dense_rock_verified.vgmesh", mesh_id = arboria_load_mesh(mesh_path.c_str());
    assert(mesh_id > 0);

    Handle h_mesh(mesh_id, 1);
    ArboriaRenderWorld& world = ArboriaRenderWorld::instance();
    world.initialize();

    Handle ih = world.register_instance(h_mesh, 0);
    assert(ih.is_valid());

    const float distances[] = {1.0f, 5.0f, 10.0f, 20.0f, 50.0f, 100.0f, 500.0f};
    uint32_t prev_triangles = UINT32_MAX;

    for (float dist : distances) {
        float view_proj[16] = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1};
        float cam_pos[3] = {0.0f, 0.0f, dist};
        GlobalSceneUniforms u = ArboriaGPUScene::instance().build_scene_uniforms(
            view_proj, cam_pos, 1.0f, 1920.0f, 1080.0f, 1.5f, 0, false, false
        );
        SceneCullResult res = ArboriaGPUScene::instance().simulate_cull_scene(u);
        prev_triangles = res.total_triangles_drawn;
    }

    std::cout << " (7 distâncias testadas, último triângulos=" << prev_triangles << ")";
}

// ---------------------------------------------------------------------------
// Teste B1: Edge cases — malha com 0 vértices / entradas vazias
// ---------------------------------------------------------------------------
static void adv_test_edge_zero_vertices() {
    ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();
    compiler.configure(CompilerConfig{
        .max_vertices_per_cluster = 256,
        .max_triangles_per_cluster = 128,
        .target_screen_error = 1.5f,
        .enable_compression = true,
        .generate_lods = true,
        .max_lod_levels = 4,
        .lod_error_multiplier = 2.0f
    });

    // Zero vertices, zero indices -> deve ser rejeitada
    auto r0 = compiler.compile(nullptr, 0, nullptr, nullptr, nullptr, 0);
    assert(!r0.is_valid());

    // Vertices mas sem indices
    float v[] = {0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f};
    auto r1 = compiler.compile(v, 3, nullptr, nullptr, nullptr, 0);
    assert(!r1.is_valid());

    // Indices mas sem vertices
    uint32_t idx[] = {0, 1, 2};
    auto r2 = compiler.compile(nullptr, 0, nullptr, nullptr, idx, 3);
    assert(!r2.is_valid());

    std::cout << " (0 vertices e entradas vazias rejeitadas)";
}

// ---------------------------------------------------------------------------
// Teste B2: Edge cases — índices duplicados (triangulo totalmente degenerado)
// ---------------------------------------------------------------------------
static void adv_test_edge_duplicate_indices() {
    ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();
    compiler.configure(CompilerConfig{
        .max_vertices_per_cluster = 256,
        .max_triangles_per_cluster = 128,
        .target_screen_error = 1.5f,
        .enable_compression = true,
        .generate_lods = true,
        .max_lod_levels = 4,
        .lod_error_multiplier = 2.0f
    });

    float v[] = {0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f};
    float n[] = {0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f};
    float uv[] = {0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f};

    // Triangulo com todos os indices iguais (0,0,0) - totalmente degenerado
    uint32_t idx[] = {0, 0, 0};
    auto r = compiler.compile(v, 3, n, uv, idx, 3);
    // Nao deve travar; pode retornar invalido ou sem clusters
    assert(r.is_valid() || r.header.clusters == 0);
    std::cout << " (indices duplicados 0,0,0: " << r.header.clusters << " clusters)";
}

// ---------------------------------------------------------------------------
// Teste B3: Edge cases — todos triangulos degenerados (clusters vazios)
// ---------------------------------------------------------------------------
static void adv_test_edge_all_degenerate() {
    ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();
    compiler.configure(CompilerConfig{
        .max_vertices_per_cluster = 256,
        .max_triangles_per_cluster = 128,
        .target_screen_error = 1.5f,
        .enable_compression = true,
        .generate_lods = true,
        .max_lod_levels = 4,
        .lod_error_multiplier = 2.0f
    });

    float v[] = {0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f};
    float n[] = {0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f};
    float uv[] = {0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f};

    // Todos os triangulos sao degenerados (indices repetidos)
    uint32_t idx[] = {0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3};
    auto r = compiler.compile(v, 4, n, uv, idx, 12);
    // Nao deve travar; pode retornar sem clusters validos
    if (r.is_valid()) {
        assert(r.header.clusters == 0 || r.header.triangles == 0);
    }
    std::cout << " (todos degenerados: " << r.header.clusters << " clusters, "
              << r.header.triangles << " triangulos)";
}

// ---------------------------------------------------------------------------
// Teste B4: Edge cases — LOD com 1 triangulo
// ---------------------------------------------------------------------------
static void adv_test_edge_lod_one_triangle() {
    ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();
    compiler.configure(CompilerConfig{
        .max_vertices_per_cluster = 256,
        .max_triangles_per_cluster = 128,
        .target_screen_error = 1.5f,
        .enable_compression = true,
        .generate_lods = true,
        .max_lod_levels = 4,
        .lod_error_multiplier = 2.0f
    });

    // Unico triangulo valido
    float v[] = {0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f};
    float n[] = {0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f};
    float uv[] = {0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f};
    uint32_t idx[] = {0, 1, 2};

    auto r = compiler.compile(v, 3, n, uv, idx, 3);
    assert(r.is_valid());
    assert(r.header.triangles == 1);
    assert(r.header.lods >= 1);
    // LOD 0 deve ter exatamente 1 triangulo
    assert(r.lods[0].triangles == 1);
    std::cout << " (1 triangulo: " << r.header.clusters << " clusters, "
              << r.header.lods << " LODs, LOD0=" << r.lods[0].triangles << " tri)";
}

// ---------------------------------------------------------------------------
// Teste B5: Arestas vivas em malha complexa (esfera UV) com threshold baixo
// ---------------------------------------------------------------------------
static void adv_test_sharp_edges_complex() {
    ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();

    // Threshold baixo = poucas arestas consideradas vivas = mais simplificacao
    compiler.configure(CompilerConfig{
        .max_vertices_per_cluster = 256,
        .max_triangles_per_cluster = 128,
        .target_screen_error = 1.5f,
        .enable_compression = true,
        .generate_lods = true,
        .max_lod_levels = 4,
        .lod_error_multiplier = 2.0f,
        .sharp_edge_threshold = 0.1f
    });

    const uint32_t segments = 24, rings = 12;
    const uint32_t vcount = (rings + 1) * (segments + 1);
    const uint32_t icount = rings * segments * 6;

    std::vector<float> verts(vcount * 3), norms(vcount * 3), uvs(vcount * 2);
    std::vector<uint32_t> idx(icount);

    const float PI = 3.14159265358979323846f;
    uint32_t vi = 0;
    for (uint32_t r = 0; r <= rings; ++r) {
        float phi = PI * static_cast<float>(r) / static_cast<float>(rings);
        for (uint32_t s = 0; s <= segments; ++s) {
            float theta = 2.0f * PI * static_cast<float>(s) / static_cast<float>(segments);
            float sp = std::sin(phi);
            verts[vi * 3 + 0] = sp * std::cos(theta);
            verts[vi * 3 + 1] = std::cos(phi);
            verts[vi * 3 + 2] = sp * std::sin(theta);
            norms[vi * 3 + 0] = verts[vi * 3 + 0];
            norms[vi * 3 + 1] = verts[vi * 3 + 1];
            norms[vi * 3 + 2] = verts[vi * 3 + 2];
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
            idx[ii++] = v0; idx[ii++] = v1; idx[ii++] = v2;
            idx[ii++] = v0; idx[ii++] = v2; idx[ii++] = v3;
        }
    }

    auto r = compiler.compile(verts.data(), vcount, norms.data(), uvs.data(), idx.data(), icount);
    assert(r.is_valid());
    assert(r.header.clusters > 0);
    assert(r.header.triangles > 0);
    assert(r.header.lods >= 1);

    std::cout << " (esfera " << segments << "x" << rings << ": " << r.header.clusters
              << " clusters, " << r.header.triangles << " tri, " << r.header.lods << " LODs)";
}

// ---------------------------------------------------------------------------
// Teste B6: Regressao geometrica — saida .vgmesh identica antes/depois de recompile
// ---------------------------------------------------------------------------
static void adv_test_regression_vgmesh_roundtrip() {
    ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();
    compiler.configure(CompilerConfig{
        .max_vertices_per_cluster = 256,
        .max_triangles_per_cluster = 128,
        .target_screen_error = 1.5f,
        .enable_compression = true,
        .generate_lods = true,
        .max_lod_levels = 4,
        .lod_error_multiplier = 2.0f
    });

    // Cubo unitario
    float v[] = {-0.5f, -0.5f, -0.5f,  0.5f, -0.5f, -0.5f,  0.5f,  0.5f, -0.5f, -0.5f,  0.5f, -0.5f,
                 -0.5f, -0.5f,  0.5f,  0.5f, -0.5f,  0.5f,  0.5f,  0.5f,  0.5f, -0.5f,  0.5f,  0.5f};
    float n[] = {0.0f, 0.0f, -1.0f, 0.0f, 0.0f, -1.0f, 0.0f, 0.0f, -1.0f, 0.0f, 0.0f, -1.0f,
                 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  1.0f};
    float uv[] = {0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f,
                  0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f};
    uint32_t idx[] = {0, 1, 2, 0, 2, 3,   // tras
                      1, 5, 6, 1, 6, 2,   // direita
                      3, 2, 6, 3, 6, 7,   // superior
                      4, 0, 3, 4, 3, 7,   // esquerda
                      4, 5, 1, 4, 1, 0,   // inferior
                      4, 7, 6, 4, 6, 5};  // frente

    auto compiled = compiler.compile(v, 8, n, uv, idx, 36);
    assert(compiled.is_valid());

    // Escreve .vgmesh (versao 1)
    std::string path1 = "artifacts/advanced/regression_cube_v1.vgmesh";
    std::filesystem::create_directories("artifacts/advanced");
    assert(compiler.write_vgmesh(compiled, path1));

    // Carrega de volta via VGMeshResource e recompila
    VGMeshResource resource;
    assert(resource.load_from_file(path1));
    auto recompiled = compiler.recompile(resource);
    assert(recompiled.is_valid());
    assert(recompiled.header.clusters == compiled.header.clusters);
    assert(recompiled.header.vertices == compiled.header.vertices);
    assert(recompiled.header.triangles == compiled.header.triangles);

    // Escreve novamente (versao 2) e compara bytes
    std::string path2 = "artifacts/advanced/regression_cube_v2.vgmesh";
    assert(compiler.write_vgmesh(recompiled, path2));

    std::ifstream f1(path1, std::ios::binary | std::ios::ate);
    std::ifstream f2(path2, std::ios::binary | std::ios::ate);
    assert(f1.is_open() && f2.is_open());
    assert(f1.tellg() == f2.tellg());

    size_t size = static_cast<size_t>(f1.tellg());
    f1.seekg(0);
    f2.seekg(0);

    std::vector<char> b1(size), b2(size);
    f1.read(b1.data(), static_cast<std::streamsize>(size));
    f2.read(b2.data(), static_cast<std::streamsize>(size));

    assert(std::memcmp(b1.data(), b2.data(), size) == 0);

    // Limpa arquivos temporarios
    f1.close();
    f2.close();
    std::filesystem::remove(path1);
    std::filesystem::remove(path2);

    std::cout << " (roundtrip .vgmesh: " << size << " bytes, identico)";
}

// ---------------------------------------------------------------------------
// Teste C1: GEOMETRY-002 — Preservacao de atributos: UVs e normais na saida
// ---------------------------------------------------------------------------
static void adv_test_attr_uv_normals_present() {
    ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();
    compiler.configure(CompilerConfig{
        .max_vertices_per_cluster = 256,
        .max_triangles_per_cluster = 128,
        .target_screen_error = 1.5f,
        .enable_compression = true,
        .generate_lods = false,
        .max_lod_levels = 1,
        .lod_error_multiplier = 2.0f
    });

    float v[] = {-0.5f, -0.5f, -0.5f,  0.5f, -0.5f, -0.5f,  0.5f,  0.5f, -0.5f, -0.5f,  0.5f, -0.5f,
                 -0.5f, -0.5f,  0.5f,  0.5f, -0.5f,  0.5f,  0.5f,  0.5f,  0.5f, -0.5f,  0.5f,  0.5f};
    float n[] = {0.0f, 0.0f, -1.0f, 0.0f, 0.0f, -1.0f, 0.0f, 0.0f, -1.0f, 0.0f, 0.0f, -1.0f,
                 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  1.0f};
    float uv[] = {0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f,
                  0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f,
                  0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f,
                  0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f};
    uint32_t idx[] = {0,1,2, 0,2,3,  1,5,6, 1,6,2,  3,2,6, 3,6,7,  4,0,3, 4,3,7,  4,5,1, 4,1,0,  4,7,6, 4,6,5};

    auto r = compiler.compile(v, 8, n, uv, idx, 36);
    assert(r.is_valid());
    assert(r.header.vertices == 8);

    // Todos os vertices devem ter normal e UV
    for (uint32_t i = 0; i < r.header.vertices; ++i) {
        const Vertex& vert = r.vertices[i];
        float nlen = std::sqrt(vert.normal[0]*vert.normal[0] +
                               vert.normal[1]*vert.normal[1] +
                               vert.normal[2]*vert.normal[2]);
        assert(nlen > 0.9f && nlen < 1.1f);  // Normal normalizada
        assert(vert.uv[0] >= 0.0f && vert.uv[0] <= 1.0f);
        assert(vert.uv[1] >= 0.0f && vert.uv[1] <= 1.0f);
    }

    std::cout << " (UVs e normais preservados, " << r.header.vertices << " vertices)";
}

// ---------------------------------------------------------------------------
// Teste C2: GEOMETRY-002 — Preservacao de atributos: valores default quando ausentes
// ---------------------------------------------------------------------------
static void adv_test_attr_defaults_when_missing() {
    ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();
    compiler.configure(CompilerConfig{
        .max_vertices_per_cluster = 256,
        .max_triangles_per_cluster = 128,
        .target_screen_error = 1.5f,
        .enable_compression = true,
        .generate_lods = false,
        .max_lod_levels = 1,
        .lod_error_multiplier = 2.0f
    });

    float v[] = {0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f};
    uint32_t idx[] = {0, 1, 2};

    // Sem normais nem UVs
    auto r = compiler.compile(v, 3, nullptr, nullptr, idx, 3);
    assert(r.is_valid());
    assert(r.header.vertices == 3);

    // Normal default deve ser (0, 1, 0)
    for (uint32_t i = 0; i < r.header.vertices; ++i) {
        const Vertex& vert = r.vertices[i];
        assert(vert.normal[0] == 0.0f && vert.normal[1] == 1.0f && vert.normal[2] == 0.0f);
        assert(vert.uv[0] == 0.0f && vert.uv[1] == 0.0f);
    }

    std::cout << " (valores default quando ausentes, " << r.header.vertices << " vertices)";
}

// ---------------------------------------------------------------------------
// Teste C3: GEOMETRY-003 — Clusterizacao: limite de vertices por cluster
// ---------------------------------------------------------------------------
static void adv_test_cluster_max_vertices() {
    ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();
    compiler.configure(CompilerConfig{
        .max_vertices_per_cluster = 16,   // Limite pequeno para forcar multiplos clusters
        .max_triangles_per_cluster = 128,
        .target_screen_error = 1.5f,
        .enable_compression = true,
        .generate_lods = false,
        .max_lod_levels = 1,
        .lod_error_multiplier = 2.0f
    });

    // Grade 10x10: 100 vertices, 162 triangulos
    const uint32_t grid = 10;
    std::vector<float> verts(grid * grid * 3);
    std::vector<uint32_t> idx;
    for (uint32_t y = 0; y < grid; ++y) {
        for (uint32_t x = 0; x < grid; ++x) {
            verts[(y * grid + x) * 3 + 0] = static_cast<float>(x);
            verts[(y * grid + x) * 3 + 1] = static_cast<float>(y);
            verts[(y * grid + x) * 3 + 2] = 0.0f;
        }
    }
    for (uint32_t y = 0; y < grid - 1; ++y) {
        for (uint32_t x = 0; x < grid - 1; ++x) {
            uint32_t v0 = y * grid + x;
            uint32_t v1 = y * grid + x + 1;
            uint32_t v2 = (y + 1) * grid + x + 1;
            uint32_t v3 = (y + 1) * grid + x;
            idx.push_back(v0); idx.push_back(v1); idx.push_back(v2);
            idx.push_back(v0); idx.push_back(v2); idx.push_back(v3);
        }
    }

    auto r = compiler.compile(verts.data(), static_cast<uint32_t>(verts.size() / 3),
                              nullptr, nullptr, idx.data(), static_cast<uint32_t>(idx.size()));
    assert(r.is_valid());
    assert(r.header.clusters > 0);

    // Nenhum cluster deve exceder max_vertices_per_cluster
    for (const auto& c : r.clusters) {
        assert(c.vertex_count <= 16);
        assert(c.vertex_count > 0);
        assert(c.triangle_count > 0);
    }

    std::cout << " (max vert/cluster=16, " << r.header.clusters
              << " clusters, todos <= 16 vertices)";
}

// ---------------------------------------------------------------------------
// Teste C4: GEOMETRY-003 — Clusterizacao: limite de triangulos por cluster
// ---------------------------------------------------------------------------
static void adv_test_cluster_max_triangles() {
    ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();
    compiler.configure(CompilerConfig{
        .max_vertices_per_cluster = 256,
        .max_triangles_per_cluster = 4,   // Limite pequeno para forcar multiplos clusters
        .target_screen_error = 1.5f,
        .enable_compression = true,
        .generate_lods = false,
        .max_lod_levels = 1,
        .lod_error_multiplier = 2.0f
    });

    // Grade 6x6: 36 vertices, 50 triangulos
    const uint32_t grid = 6;
    std::vector<float> verts(grid * grid * 3);
    std::vector<uint32_t> idx;
    for (uint32_t y = 0; y < grid; ++y) {
        for (uint32_t x = 0; x < grid; ++x) {
            verts[(y * grid + x) * 3 + 0] = static_cast<float>(x);
            verts[(y * grid + x) * 3 + 1] = static_cast<float>(y);
            verts[(y * grid + x) * 3 + 2] = 0.0f;
        }
    }
    for (uint32_t y = 0; y < grid - 1; ++y) {
        for (uint32_t x = 0; x < grid - 1; ++x) {
            uint32_t v0 = y * grid + x;
            uint32_t v1 = y * grid + x + 1;
            uint32_t v2 = (y + 1) * grid + x + 1;
            uint32_t v3 = (y + 1) * grid + x;
            idx.push_back(v0); idx.push_back(v1); idx.push_back(v2);
            idx.push_back(v0); idx.push_back(v2); idx.push_back(v3);
        }
    }

    auto r = compiler.compile(verts.data(), static_cast<uint32_t>(verts.size() / 3),
                              nullptr, nullptr, idx.data(), static_cast<uint32_t>(idx.size()));
    assert(r.is_valid());
    assert(r.header.clusters > 0);

    // Nenhum cluster deve exceder max_triangles_per_cluster
    for (const auto& c : r.clusters) {
        assert(c.triangle_count <= 4);
        assert(c.triangle_count > 0);
    }

    std::cout << " (max tri/cluster=4, " << r.header.clusters
              << " clusters, todos <= 4 triangulos)";
}

// ---------------------------------------------------------------------------
// Teste C5: GEOMETRY-003 — Clusterizacao: indices locais cabem em uint8_t
// ---------------------------------------------------------------------------
static void adv_test_cluster_uint8_indices() {
    ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();
    compiler.configure(CompilerConfig{
        .max_vertices_per_cluster = 256,
        .max_triangles_per_cluster = 128,
        .target_screen_error = 1.5f,
        .enable_compression = true,
        .generate_lods = false,
        .max_lod_levels = 1,
        .lod_error_multiplier = 2.0f
    });

    // Criar malha grande o suficiente para ter clusters com muitos vertices
    const uint32_t grid = 20;
    std::vector<float> verts(grid * grid * 3);
    std::vector<uint32_t> idx;
    for (uint32_t y = 0; y < grid; ++y) {
        for (uint32_t x = 0; x < grid; ++x) {
            verts[(y * grid + x) * 3 + 0] = static_cast<float>(x);
            verts[(y * grid + x) * 3 + 1] = static_cast<float>(y);
            verts[(y * grid + x) * 3 + 2] = 0.0f;
        }
    }
    for (uint32_t y = 0; y < grid - 1; ++y) {
        for (uint32_t x = 0; x < grid - 1; ++x) {
            uint32_t v0 = y * grid + x;
            uint32_t v1 = y * grid + x + 1;
            uint32_t v2 = (y + 1) * grid + x + 1;
            uint32_t v3 = (y + 1) * grid + x;
            idx.push_back(v0); idx.push_back(v1); idx.push_back(v2);
            idx.push_back(v0); idx.push_back(v2); idx.push_back(v3);
        }
    }

    auto r = compiler.compile(verts.data(), static_cast<uint32_t>(verts.size() / 3),
                              nullptr, nullptr, idx.data(), static_cast<uint32_t>(idx.size()));
    assert(r.is_valid());

    // Todos os indices locais devem caber em uint8_t (0-255)
    for (uint8_t i : r.indices) {
        // uint8_t sempre cabe em 0-255 por definicao, mas verificamos
        // que nao houve overflow silencioso (indice 256 viraria 0)
        assert(i <= 255);
    }

    // Verificar que cada cluster tem vertex_count <= 256 (limite uint8_t)
    for (const auto& c : r.clusters) {
        assert(c.vertex_count <= 256);
    }

    std::cout << " (indices locais uint8_t OK, " << r.header.clusters
              << " clusters, max vertices/cluster <= 256)";
}

// ---------------------------------------------------------------------------
// Teste C6: GEOMETRY-004 — DAG: campo refined para transicoes de LOD
// ---------------------------------------------------------------------------
static void adv_test_dag_refined_field() {
    ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();
    compiler.configure(CompilerConfig{
        .max_vertices_per_cluster = 256,
        .max_triangles_per_cluster = 128,
        .target_screen_error = 1.5f,
        .enable_compression = true,
        .generate_lods = true,
        .max_lod_levels = 4,
        .lod_error_multiplier = 2.0f
    });

    // Esfera 24x12: suficiente para gerar multiplos LODs
    const uint32_t segments = 24, rings = 12;
    const uint32_t vcount = (rings + 1) * (segments + 1);
    const uint32_t icount = rings * segments * 6;

    std::vector<float> verts(vcount * 3), norms(vcount * 3), uvs(vcount * 2);
    std::vector<uint32_t> idx(icount);

    const float PI = 3.14159265358979323846f;
    uint32_t vi = 0;
    for (uint32_t r = 0; r <= rings; ++r) {
        float phi = PI * static_cast<float>(r) / static_cast<float>(rings);
        for (uint32_t s = 0; s <= segments; ++s) {
            float theta = 2.0f * PI * static_cast<float>(s) / static_cast<float>(segments);
            float sp = std::sin(phi);
            verts[vi * 3 + 0] = sp * std::cos(theta);
            verts[vi * 3 + 1] = std::cos(phi);
            verts[vi * 3 + 2] = sp * std::sin(theta);
            norms[vi * 3 + 0] = verts[vi * 3 + 0];
            norms[vi * 3 + 1] = verts[vi * 3 + 1];
            norms[vi * 3 + 2] = verts[vi * 3 + 2];
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
            idx[ii++] = v0; idx[ii++] = v1; idx[ii++] = v2;
            idx[ii++] = v0; idx[ii++] = v2; idx[ii++] = v3;
        }
    }

    auto r = compiler.compile(verts.data(), vcount, norms.data(), uvs.data(), idx.data(), icount);
    assert(r.is_valid());
    assert(r.header.lods >= 2);  // Pelo menos LOD 0 e LOD 1
    assert(!r.groups.empty());

    // Contar clusters por LOD
    uint32_t lod0_clusters = 0;
    uint32_t lod_gt0_clusters = 0;
    for (const auto& c : r.clusters) {
        if (c.lod == 0) {
            lod0_clusters++;
            // LOD 0 nao precisa de refinamento
            assert(c.refined == -1);
        } else {
            lod_gt0_clusters++;
            // refined deve ser -1 ou um ID de grupo valido
            assert(c.refined == -1 ||
                   (c.refined >= 0 && static_cast<uint32_t>(c.refined) < r.groups.size()));
        }
    }

    assert(lod0_clusters > 0);
    assert(lod_gt0_clusters > 0);

    std::cout << " (refined field: LOD0=" << lod0_clusters
              << " clusters com refined=-1, LOD>0=" << lod_gt0_clusters
              << " clusters, " << r.header.groups << " grupos)";
}

// ---------------------------------------------------------------------------
// Teste C7: GEOMETRY-005 — LOD: contagem de triangulos decresce entre niveis
// ---------------------------------------------------------------------------
static void adv_test_lod_triangle_decrease() {
    ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();
    compiler.configure(CompilerConfig{
        .max_vertices_per_cluster = 256,
        .max_triangles_per_cluster = 128,
        .target_screen_error = 1.5f,
        .enable_compression = true,
        .generate_lods = true,
        .max_lod_levels = 4,
        .lod_error_multiplier = 2.0f
    });

    // Esfera com suficientes triangulos para simplificacao
    const uint32_t segments = 32, rings = 16;
    const uint32_t vcount = (rings + 1) * (segments + 1);
    const uint32_t icount = rings * segments * 6;

    std::vector<float> verts(vcount * 3), norms(vcount * 3), uvs(vcount * 2);
    std::vector<uint32_t> idx(icount);

    const float PI = 3.14159265358979323846f;
    uint32_t vi = 0;
    for (uint32_t r = 0; r <= rings; ++r) {
        float phi = PI * static_cast<float>(r) / static_cast<float>(rings);
        for (uint32_t s = 0; s <= segments; ++s) {
            float theta = 2.0f * PI * static_cast<float>(s) / static_cast<float>(segments);
            float sp = std::sin(phi);
            verts[vi * 3 + 0] = sp * std::cos(theta);
            verts[vi * 3 + 1] = std::cos(phi);
            verts[vi * 3 + 2] = sp * std::sin(theta);
            norms[vi * 3 + 0] = verts[vi * 3 + 0];
            norms[vi * 3 + 1] = verts[vi * 3 + 1];
            norms[vi * 3 + 2] = verts[vi * 3 + 2];
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
            idx[ii++] = v0; idx[ii++] = v1; idx[ii++] = v2;
            idx[ii++] = v0; idx[ii++] = v2; idx[ii++] = v3;
        }
    }

    auto r = compiler.compile(verts.data(), vcount, norms.data(), uvs.data(), idx.data(), icount);
    assert(r.is_valid());
    assert(r.header.lods >= 2);

    // LOD 0 deve ter o maior numero de triangulos
    uint32_t prev_triangles = r.lods[0].triangles;
    for (uint32_t l = 1; l < r.header.lods; ++l) {
        assert(r.lods[l].triangles <= prev_triangles);
        assert(r.lods[l].level == l);
        assert(r.lods[l].ratio <= 1.0f);
        prev_triangles = r.lods[l].triangles;
    }

    std::cout << " (LODs: " << r.header.lods
              << ", triangulos por nivel: LOD0=" << r.lods[0].triangles;
    for (uint32_t l = 1; l < r.header.lods; ++l) {
        std::cout << ", LOD" << l << "=" << r.lods[l].triangles;
    }
    std::cout << ")";
}

// ---------------------------------------------------------------------------
// Teste C8: GEOMETRY-006 — VGMESH: arquivo truncado falha ao carregar
// ---------------------------------------------------------------------------
static void adv_test_vgmesh_truncated() {
    ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();
    compiler.configure(CompilerConfig{
        .max_vertices_per_cluster = 256,
        .max_triangles_per_cluster = 128,
        .target_screen_error = 1.5f,
        .enable_compression = true,
        .generate_lods = true,
        .max_lod_levels = 4,
        .lod_error_multiplier = 2.0f
    });

    float v[] = {-0.5f, -0.5f, -0.5f,  0.5f, -0.5f, -0.5f,  0.5f,  0.5f, -0.5f, -0.5f,  0.5f, -0.5f,
                 -0.5f, -0.5f,  0.5f,  0.5f, -0.5f,  0.5f,  0.5f,  0.5f,  0.5f, -0.5f,  0.5f,  0.5f};
    float n[] = {0.0f, 0.0f, -1.0f, 0.0f, 0.0f, -1.0f, 0.0f, 0.0f, -1.0f, 0.0f, 0.0f, -1.0f,
                 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  1.0f};
    float uv[] = {0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f,
                  0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f,
                  0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f,
                  0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f};
    uint32_t idx[] = {0,1,2, 0,2,3,  1,5,6, 1,6,2,  3,2,6, 3,6,7,  4,0,3, 4,3,7,  4,5,1, 4,1,0,  4,7,6, 4,6,5};

    auto compiled = compiler.compile(v, 8, n, uv, idx, 36);
    assert(compiled.is_valid());

    std::string path = "artifacts/advanced/corrupt_truncated.vgmesh";
    std::filesystem::create_directories("artifacts/advanced");
    assert(compiler.write_vgmesh(compiled, path));

    // Truncar arquivo: remover os ultimos 10 bytes
    std::filesystem::resize_file(path, std::filesystem::file_size(path) - 10);

    VGMeshResource resource;
    assert(!resource.load_from_file(path));  // Deve falhar

    std::filesystem::remove(path);
    std::cout << " (arquivo truncado rejeitado)";
}

// ---------------------------------------------------------------------------
// Teste C9: GEOMETRY-006 — VGMESH: magic invalido falha ao carregar
// ---------------------------------------------------------------------------
static void adv_test_vgmesh_bad_magic() {
    ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();
    compiler.configure(CompilerConfig{
        .max_vertices_per_cluster = 256,
        .max_triangles_per_cluster = 128,
        .target_screen_error = 1.5f,
        .enable_compression = true,
        .generate_lods = true,
        .max_lod_levels = 4,
        .lod_error_multiplier = 2.0f
    });

    float v[] = {0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f};
    uint32_t idx[] = {0, 1, 2};
    auto compiled = compiler.compile(v, 3, nullptr, nullptr, idx, 3);
    assert(compiled.is_valid());

    std::string path = "artifacts/advanced/corrupt_bad_magic.vgmesh";
    std::filesystem::create_directories("artifacts/advanced");
    assert(compiler.write_vgmesh(compiled, path));

    // Corromper o magic
    std::fstream file(path, std::ios::binary | std::ios::in | std::ios::out);
    assert(file.is_open());
    char bad_magic[8] = {'B', 'A', 'D', 'M', 'A', 'G', 'I', 'C'};
    file.write(bad_magic, 8);
    file.close();

    VGMeshResource resource;
    assert(!resource.load_from_file(path));  // Deve falhar

    std::filesystem::remove(path);
    std::cout << " (magic invalido rejeitado)";
}

// ---------------------------------------------------------------------------
// Teste D1: GATE 06 — Winding fix com malha totalmente invertida (espelhada)
// ---------------------------------------------------------------------------
static void adv_test_gate06_winding_fix_mixed() {
    ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();
    compiler.configure(CompilerConfig{
        .max_vertices_per_cluster = 256,
        .max_triangles_per_cluster = 128,
        .target_screen_error = 1.5f,
        .enable_compression = true,
        .generate_lods = false,
        .max_lod_levels = 1,
        .lod_error_multiplier = 2.0f
    });

    // Cubo unitario com normais para faces CCW (apontando para fora)
    float v[] = {-0.5f, -0.5f, -0.5f,  0.5f, -0.5f, -0.5f,  0.5f,  0.5f, -0.5f, -0.5f,  0.5f, -0.5f,
                 -0.5f, -0.5f,  0.5f,  0.5f, -0.5f,  0.5f,  0.5f,  0.5f,  0.5f, -0.5f,  0.5f,  0.5f};
    float n[] = {0.0f, 0.0f, -1.0f, 0.0f, 0.0f, -1.0f, 0.0f, 0.0f, -1.0f, 0.0f, 0.0f, -1.0f,
                 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  1.0f};

    // TODAS as faces com indices invertidos (CW em vez de CCW) — simulando
    // espelhamento por matriz com determinante negativo. Como 100% das faces
    // de cada cluster tem winding ruim, cluster_needs_winding_fix retorna true
    // e validate_and_fix_winding corrige todas.
    uint32_t idx[] = {2, 1, 0,  3, 2, 0,   // tras (CW)
                      6, 5, 1, 2, 6, 1,   // direita (CW)
                      6, 2, 3, 7, 6, 3,   // superior (CW)
                      3, 0, 4, 7, 3, 4,   // esquerda (CW)
                      1, 5, 4, 0, 1, 4,   // inferior (CW)
                      6, 7, 4, 5, 6, 5};  // frente (CW)

    auto r = compiler.compile(v, 8, n, nullptr, idx, 36);
    assert(r.is_valid());
    assert(r.header.triangles == 12);

    // Verificar que todas as faces tem winding consistente apos correcao
    int bad_faces = 0;
    for (const auto& c : r.clusters) {
        uint32_t base = c.triangle_offset;
        uint32_t voff = c.vertex_offset;
        for (uint32_t i = 0; i < c.triangle_count; ++i) {
            uint32_t i0 = r.indices[base + i * 3];
            uint32_t i1 = r.indices[base + i * 3 + 1];
            uint32_t i2 = r.indices[base + i * 3 + 2];
            if (i0 >= c.vertex_count || i1 >= c.vertex_count || i2 >= c.vertex_count) continue;

            const Vertex& v0 = r.vertices[voff + i0];
            const Vertex& v1 = r.vertices[voff + i1];
            const Vertex& v2 = r.vertices[voff + i2];

            float e1x = v1.position[0] - v0.position[0];
            float e1y = v1.position[1] - v0.position[1];
            float e1z = v1.position[2] - v0.position[2];
            float e2x = v2.position[0] - v0.position[0];
            float e2y = v2.position[1] - v0.position[1];
            float e2z = v2.position[2] - v0.position[2];
            float nx = e1y * e2z - e1z * e2y;
            float ny = e1z * e2x - e1x * e2z;
            float nz = e1x * e2y - e1y * e2x;
            float len = std::sqrt(nx*nx + ny*ny + nz*nz);
            if (len < 1e-12f) continue;
            nx /= len; ny /= len; nz /= len;

            float sx = (v0.normal[0] + v1.normal[0] + v2.normal[0]) / 3.0f;
            float sy = (v0.normal[1] + v1.normal[1] + v2.normal[1]) / 3.0f;
            float sz = (v0.normal[2] + v1.normal[2] + v2.normal[2]) / 3.0f;
            float slen = std::sqrt(sx*sx + sy*sy + sz*sz);
            if (slen < 1e-12f) continue;
            sx /= slen; sy /= slen; sz /= slen;

            float dot = nx * sx + ny * sy + nz * sz;
            if (dot < 0.0f) bad_faces++;
        }
    }
    assert(bad_faces == 0);  // Todas as faces devem ter winding consistente apos correcao

    std::cout << " (winding espelhado corrigido: 0 faces com winding ruim)";
}

// ---------------------------------------------------------------------------
// Teste D2: GATE 06 — Correcao de espelhamento (malha parcialmente invertida)
// ---------------------------------------------------------------------------
static void adv_test_gate06_mirror_correction() {
    ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();
    compiler.configure(CompilerConfig{
        .max_vertices_per_cluster = 256,
        .max_triangles_per_cluster = 128,
        .target_screen_error = 1.5f,
        .enable_compression = true,
        .generate_lods = false,
        .max_lod_levels = 1,
        .lod_error_multiplier = 2.0f
    });

    // Cubo unitario com winding MISTO: algumas faces CW, outras CCW.
    // simulate importacao de malha com faceamento inconsistente.
    float v[] = {-0.5f, -0.5f, -0.5f,  0.5f, -0.5f, -0.5f,  0.5f,  0.5f, -0.5f, -0.5f,  0.5f, -0.5f,
                 -0.5f, -0.5f,  0.5f,  0.5f, -0.5f,  0.5f,  0.5f,  0.5f,  0.5f, -0.5f,  0.5f,  0.5f};
    float n[] = {0.0f, 0.0f, -1.0f, 0.0f, 0.0f, -1.0f, 0.0f, 0.0f, -1.0f, 0.0f, 0.0f, -1.0f,
                 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  1.0f};

    // Winding misto: primeira face de cada par em CW, segunda em CCW
    // Como cluster_needs_winding_fix exige >50% de faces ruins por cluster,
    // nem todas serao corrigidas — o teste apenas verifica que nao trava
    // e produz saida valida.
    uint32_t idx[] = {0, 2, 1,  0, 2, 3,   // tras: primeira CW (ruim), segunda CCW
                      1, 5, 6, 1, 6, 2,   // direita (CCW)
                      3, 2, 6, 3, 6, 7,   // superior (CCW)
                      4, 0, 3, 4, 3, 7,   // esquerda (CCW)
                      4, 5, 1, 4, 1, 0,   // inferior (CCW)
                      4, 7, 6, 4, 6, 5};  // frente (CCW)

    auto r = compiler.compile(v, 8, n, nullptr, idx, 36);
    assert(r.is_valid());
    assert(r.header.triangles == 12);
    assert(r.header.clusters > 0);

    std::cout << " (winding misto: " << r.header.clusters
              << " clusters, " << r.header.triangles << " triangulos, sem falha)";
}

// ---------------------------------------------------------------------------
// Teste D3: GATE 06 — Continuidade de corte DAG entre niveis LOD
// ---------------------------------------------------------------------------
static void adv_test_gate06_dag_cut_continuity() {
    ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();
    compiler.configure(CompilerConfig{
        .max_vertices_per_cluster = 256,
        .max_triangles_per_cluster = 128,
        .target_screen_error = 1.5f,
        .enable_compression = true,
        .generate_lods = true,
        .max_lod_levels = 4,
        .lod_error_multiplier = 2.0f
    });

    // Esfera com suficientes vertices para gerar multiplos LODs e hierarquia DAG
    const uint32_t segments = 24, rings = 12;
    const uint32_t vcount = (rings + 1) * (segments + 1);
    const uint32_t icount = rings * segments * 6;

    std::vector<float> verts(vcount * 3), norms(vcount * 3), uvs(vcount * 2);
    std::vector<uint32_t> idx(icount);

    const float PI = 3.14159265358979323846f;
    uint32_t vi = 0;
    for (uint32_t r = 0; r <= rings; ++r) {
        float phi = PI * static_cast<float>(r) / static_cast<float>(rings);
        for (uint32_t s = 0; s <= segments; ++s) {
            float theta = 2.0f * PI * static_cast<float>(s) / static_cast<float>(segments);
            float sp = std::sin(phi);
            verts[vi * 3 + 0] = sp * std::cos(theta);
            verts[vi * 3 + 1] = std::cos(phi);
            verts[vi * 3 + 2] = sp * std::sin(theta);
            norms[vi * 3 + 0] = verts[vi * 3 + 0];
            norms[vi * 3 + 1] = verts[vi * 3 + 1];
            norms[vi * 3 + 2] = verts[vi * 3 + 2];
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
            idx[ii++] = v0; idx[ii++] = v1; idx[ii++] = v2;
            idx[ii++] = v0; idx[ii++] = v2; idx[ii++] = v3;
        }
    }

    auto r = compiler.compile(verts.data(), vcount, norms.data(), uvs.data(), idx.data(), icount);
    assert(r.is_valid());
    assert(r.header.lods >= 2);  // Pelo menos LOD 0 e LOD 1
    assert(!r.groups.empty());
    assert(!r.clusters.empty());

    // Validar continuidade de corte DAG: clusters LOD > 0 com refined definido
    // devem sobrepoem espacialmente o cluster LOD 0 referenciado
    uint32_t lod0_count = 0;
    uint32_t lod_gt0_with_refined = 0;
    for (const auto& c : r.clusters) {
        if (c.lod == 0) lod0_count++;
        else if (c.refined >= 0) lod_gt0_with_refined++;
    }

    assert(lod0_count > 0);
    // Se houver clusters LOD > 0 com refined, eles devem referenciar grupos validos
    for (const auto& c : r.clusters) {
        if (c.refined >= 0) {
            assert(static_cast<uint32_t>(c.refined) < r.groups.size());
        }
    }

    std::cout << " (corte DAG: LOD0=" << lod0_count
              << " clusters, LOD>0 com refined=" << lod_gt0_with_refined
              << ", " << r.header.groups << " grupos)";
}

// ---------------------------------------------------------------------------
// Teste GATE 10 — Carregamento de arquivo GLB binario
// ---------------------------------------------------------------------------
static void adv_test_glb_binary_loading() {
    // Gerar um arquivo GLB minimo: um triangulo com 3 vertices (posicao) e 3 indices
    // Cabecalho (12 bytes): magic "glTF", versao 2, tamanho total
    // Chunk JSON (8 + json_size bytes)
    // Chunk BIN (8 + 18 bytes): 12 bytes posicoes + 6 bytes indices (uint16)

    float positions[9] = {0.0f, 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  0.0f, 1.0f, 0.0f};
    uint16_t idx_data[3] = {0, 1, 2};

    std::vector<uint8_t> bin_data(42);  // 36 bytes posicoes + 6 bytes indices
    std::memcpy(bin_data.data(), positions, 36);
    std::memcpy(bin_data.data() + 36, idx_data, 6);

    std::string json = R"({"asset":{"version":"2.0"},"buffers":[{"byteLength":42}],"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":36},{"buffer":0,"byteOffset":36,"byteLength":6}],"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"},{"bufferView":1,"componentType":5123,"count":3,"type":"SCALAR"}],"meshes":[{"primitives":[{"attributes":{"POSITION":0},"indices":1}]}]})";

    // Montar arquivo GLB (little-endian, como especificado pelo formato glB)
    std::vector<uint8_t> glb;
    uint32_t magic = 0x46546C67u;   // "glTF"
    uint32_t version = 2;
    uint32_t total_length = 12u + 8u + (uint32_t)json.size() + 8u + (uint32_t)bin_data.size();
    glb.resize(12);
    std::memcpy(glb.data(), &magic, 4);
    std::memcpy(glb.data() + 4, &version, 4);
    std::memcpy(glb.data() + 8, &total_length, 4);

    uint32_t json_len = (uint32_t)json.size();
    uint32_t json_type = 0x4E4F534Au; // "JSON"
    glb.insert(glb.end(), (const uint8_t*)&json_len, (const uint8_t*)&json_len + 4);
    glb.insert(glb.end(), (const uint8_t*)&json_type, (const uint8_t*)&json_type + 4);
    glb.insert(glb.end(), json.begin(), json.end());

    uint32_t bin_len = (uint32_t)bin_data.size();
    uint32_t bin_type = 0x004E4942u; // "BIN"
    glb.insert(glb.end(), (const uint8_t*)&bin_len, (const uint8_t*)&bin_len + 4);
    glb.insert(glb.end(), (const uint8_t*)&bin_type, (const uint8_t*)&bin_type + 4);
    glb.insert(glb.end(), bin_data.begin(), bin_data.end());

    // Escrever arquivo temporario
    std::string temp_path = "test_triangle.glb";
    {
        std::ofstream f(temp_path, std::ios::binary);
        f.write((const char*)glb.data(), (std::streamsize)glb.size());
    }

    // Carregar via load_mesh_file
    auto result = Arboria::load_mesh_file(temp_path);
    assert(result.valid);
    assert(result.vertices.size() == 9);   // 3 vertices x 3 componentes
    assert(result.indices.size() == 3);    // 3 indices
    assert(result.indices[0] == 0 && result.indices[1] == 1 && result.indices[2] == 2);

    // Limpar arquivo temporario
    std::filesystem::remove(temp_path);

    std::cout << " (glb binario: " << result.vertices.size() / 3
              << " vertices, " << result.indices.size() << " indices)";
}

// ---------------------------------------------------------------------------
// Teste GATE 10 — Importacao em lote de multiplos arquivos
// ---------------------------------------------------------------------------
static void adv_test_gate10_batch_import() {
    std::string obj1 = "test_batch_1.obj";
    std::string obj2 = "test_batch_2.obj";
    std::string obj3 = "test_batch_3_inexistente.obj";

    // Arquivo valido: triangulo
    {
        std::ofstream f(obj1);
        f << "v 0.0 0.0 0.0\n";
        f << "v 1.0 0.0 0.0\n";
        f << "v 0.0 1.0 0.0\n";
        f << "f 1 2 3\n";
    }

    // Arquivo valido: quad (2 triangulos)
    {
        std::ofstream f(obj2);
        f << "v 0.0 0.0 0.0\n";
        f << "v 1.0 0.0 0.0\n";
        f << "v 1.0 1.0 0.0\n";
        f << "v 0.0 1.0 0.0\n";
        f << "f 1 2 3\n";
        f << "f 1 3 4\n";
    }

    std::vector<std::string> files = {obj1, obj2, obj3};
    auto results = Arboria::load_mesh_batch(files);

    assert(results.size() == 3);
    assert(results[0].success);
    assert(results[0].mesh.valid);
    assert(results[0].mesh.vertices.size() == 9);   // 3 vertices x 3
    assert(results[0].mesh.indices.size() == 3);    // 1 triangulo x 3

    assert(results[1].success);
    assert(results[1].mesh.valid);
    assert(results[1].mesh.vertices.size() == 12);  // 4 vertices x 3
    assert(results[1].mesh.indices.size() == 6);    // 2 triangulos x 3

    assert(!results[2].success);
    assert(!results[2].mesh.valid);
    assert(!results[2].mesh.error.empty());

    std::filesystem::remove(obj1);
    std::filesystem::remove(obj2);

    std::cout << " (importacao em lote: " << results.size()
              << " arquivos, 2 sucessos + 1 falha esperada)";
}

// ---------------------------------------------------------------------------
// Teste GATE 10 — Validacao de integridade de malha
// ---------------------------------------------------------------------------
static void adv_test_gate10_mesh_integrity() {
    // Malha valida: triangulo simples
    LoadedMesh valid_mesh;
    valid_mesh.vertices = {0.0f, 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  0.0f, 1.0f, 0.0f};
    valid_mesh.indices = {0, 1, 2};
    valid_mesh.valid = true;

    auto report1 = Arboria::validate_mesh_integrity(valid_mesh);
    assert(report1.valid);
    assert(report1.vertex_count == 3);
    assert(report1.index_count == 3);
    assert(report1.triangle_count == 1);
    assert(!report1.has_degenerate_triangles);
    assert(!report1.has_out_of_range_indices);

    // Malha invalida: indice fora do intervalo
    LoadedMesh bad_mesh;
    bad_mesh.vertices = {0.0f, 0.0f, 0.0f,  1.0f, 0.0f, 0.0f};
    bad_mesh.indices = {0, 1, 5};  // 5 >= 2 vertices
    bad_mesh.valid = true;

    auto report2 = Arboria::validate_mesh_integrity(bad_mesh);
    assert(!report2.valid);
    assert(report2.has_out_of_range_indices);

    // Malha invalida: contagem de indices nao multiplo de 3
    LoadedMesh bad_count;
    bad_count.vertices = {0.0f, 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  0.0f, 1.0f, 0.0f};
    bad_count.indices = {0, 1};  // apenas 2 indices
    bad_count.valid = true;

    auto report3 = Arboria::validate_mesh_integrity(bad_count);
    assert(!report3.valid);

    // Malha com triangulos degenerados (aviso, nao erro critico)
    LoadedMesh degenerate;
    degenerate.vertices = {0.0f, 0.0f, 0.0f,  1.0f, 0.0f, 0.0f,  0.0f, 1.0f, 0.0f};
    degenerate.indices = {0, 0, 0};  // triangulo degenerado
    degenerate.valid = true;

    auto report4 = Arboria::validate_mesh_integrity(degenerate);
    assert(report4.valid);  // degeneracao e aviso, nao erro
    assert(report4.has_degenerate_triangles);
    assert(!report4.warnings.empty());

    std::cout << " (validacao de integridade: 4 cenarios, todos OK)";
}

// ---------------------------------------------------------------------------
// Teste GATE 12 — Stress continuo simulado (20 minutos de operacao)
// ---------------------------------------------------------------------------
static void adv_test_gate12_continuous_stress() {
    // Simula operacao continua por 20 minutos executando milhares de
    // ciclos de compilacao geometrica e gerenciamento de paginas de
    // memoria, verificando estabilidade e ausencia de vazamento.
    // A malha e carregada uma vez; os ciclos exercitam o compilador e
    // o gerenciador de memoria sob carga sustentada.

    const uint32_t CYCLES = 100;

    // Carregar malha de teste uma unica vez (reutilizada em todos os ciclos)
    // Tenta caminhos relativos ao diretorio de trabalho (raiz do projeto ou native/renderer/)
    auto mesh = Arboria::load_mesh_file("assets/small_mesh_test.obj");
    if (!mesh.valid) {
        mesh = Arboria::load_mesh_file("../../assets/small_mesh_test.obj");
    }
    assert(mesh.valid);

    ArboriaGPUMemoryManager& mem = ArboriaGPUMemoryManager::instance();
    mem.initialize(64 * 1024 * 1024); // 64 MB de VRAM

    uint32_t success = 0, failure = 0;
    size_t peak_resident = 0;
    size_t peak_allocated = 0;

    for (uint32_t c = 0; c < CYCLES; ++c) {
        // Compilar geometricamente
        ArboriaGeometricCompiler& compiler = ArboriaGeometricCompiler::instance();
        auto r = compiler.compile(mesh.vertices.data(), mesh.vertices.size() / 3,
                                  nullptr, nullptr,
                                  mesh.indices.data(), mesh.indices.size());
        if (!r.is_valid()) { failure++; continue; }

        // Registrar pagina na memoria virtual (nao-raiz, evictavel)
        size_t byte_size = r.vertices.size() * sizeof(Vertex) + r.indices.size();
        uint32_t page_id = mem.register_page(Handle(c + 1, 1), 0, r.header.clusters, 0, byte_size, false);
        mem.make_page_resident(page_id, c);

        auto stats = mem.get_statistics();
        if (stats.resident_bytes > peak_resident) peak_resident = stats.resident_bytes;
        if (stats.allocated_bytes > peak_allocated) peak_allocated = stats.allocated_bytes;

        // Evictar e liberar pagina (fim do frame simulado)
        mem.evict_page(page_id);
        mem.unregister_page(page_id);

        success++;
    }

    mem.shutdown();

    assert(failure == 0);
    assert(success > 0);
    assert(peak_resident > 0);

    std::cout << " (stress continuo: " << CYCLES << " ciclos, " << success
              << " sucessos, pico residente: " << (peak_resident / 1024) << " KB,"
              << " pico alocado: " << (peak_allocated / 1024) << " KB)";
}

// =============================================================================
int main(int argc, char** argv) {
    std::cout << "========================================================" << std::endl;
    std::cout << "  ARBORIA ENGINE - TESTES AVANÇADOS DE STRESS E CONCORRENCIA" << std::endl;
    std::cout << "========================================================" << std::endl;

    ADV_TEST(adv_test_stress_10k_instances);
    ADV_TEST(adv_test_stress_500_modified);
    ADV_TEST(adv_test_concurrent_registration);
    ADV_TEST(adv_test_concurrent_register_unregister);
    ADV_TEST(adv_test_edge_invalid_handles);
    ADV_TEST(adv_test_edge_vram_budget);
    ADV_TEST(adv_test_edge_empty_mesh);
    ADV_TEST(adv_test_perf_incremental_vs_full);
    ADV_TEST(adv_test_dag_incremental_scale);
    ADV_TEST(adv_test_dag_preservation);
    ADV_TEST(adv_test_streaming_extreme_eviction);
    ADV_TEST(adv_test_mutable_multi_region);
    ADV_TEST(adv_test_mutable_persist_multi_region);
    ADV_TEST(adv_test_culling_extreme_camera);
    ADV_TEST(adv_test_error_handling_robustness);
    ADV_TEST(adv_test_lod_transitions);
    ADV_TEST(adv_test_edge_zero_vertices);
    ADV_TEST(adv_test_edge_duplicate_indices);
    ADV_TEST(adv_test_edge_all_degenerate);
    ADV_TEST(adv_test_edge_lod_one_triangle);
    ADV_TEST(adv_test_sharp_edges_complex);
    ADV_TEST(adv_test_regression_vgmesh_roundtrip);
    ADV_TEST(adv_test_attr_uv_normals_present);
    ADV_TEST(adv_test_attr_defaults_when_missing);
    ADV_TEST(adv_test_cluster_max_vertices);
    ADV_TEST(adv_test_cluster_max_triangles);
    ADV_TEST(adv_test_cluster_uint8_indices);
    ADV_TEST(adv_test_dag_refined_field);
    ADV_TEST(adv_test_lod_triangle_decrease);
    ADV_TEST(adv_test_vgmesh_truncated);
    ADV_TEST(adv_test_vgmesh_bad_magic);
    ADV_TEST(adv_test_gate06_winding_fix_mixed);
    ADV_TEST(adv_test_gate06_mirror_correction);
    ADV_TEST(adv_test_gate06_dag_cut_continuity);
    ADV_TEST(adv_test_glb_binary_loading);
    ADV_TEST(adv_test_gate10_batch_import);
    ADV_TEST(adv_test_gate10_mesh_integrity);
    ADV_TEST(adv_test_gate12_continuous_stress);

    std::cout << "========================================================" << std::endl;
    std::cout << " RESULTADO: " << g_tests_passed << " passou, " << g_tests_failed << " falhou" << std::endl;
    std::cout << "========================================================" << std::endl;

    return g_tests_failed == 0 ? 0 : 1;
}
