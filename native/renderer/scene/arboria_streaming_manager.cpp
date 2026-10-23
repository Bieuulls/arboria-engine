#include "arboria_streaming_manager.h"
#include "arboria_instance_registry.h"
#include <iostream>
#include <cmath>

namespace Arboria {

ArboriaStreamingManager& ArboriaStreamingManager::instance() {
    static ArboriaStreamingManager s_instance;
    return s_instance;
}

void ArboriaStreamingManager::initialize(size_t vram_budget_bytes) {
    std::lock_guard<std::mutex> lock(m_mutex);
    ArboriaGPUMemoryManager::instance().initialize(vram_budget_bytes);
    m_profiles.clear();
    m_initialized = true;
    std::cout << "[ArboriaStreamingManager] Inicializado com sucesso. Orcamento VRAM: "
              << (vram_budget_bytes / (1024 * 1024)) << " MB." << std::endl;
}

void ArboriaStreamingManager::shutdown() {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_profiles.clear();
    ArboriaGPUMemoryManager::instance().shutdown();
    m_initialized = false;
    std::cout << "[ArboriaStreamingManager] Finalizado com sucesso." << std::endl;
}

void ArboriaStreamingManager::set_vram_budget(size_t bytes) {
    ArboriaGPUMemoryManager::instance().set_budget(bytes);
}

bool ArboriaStreamingManager::register_mesh_streaming(Handle mesh_handle, uint32_t total_clusters, float bounding_radius) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (!mesh_handle.is_valid() || total_clusters == 0) {
        return false;
    }

    MeshStreamingProfile profile{};
    profile.mesh_handle = mesh_handle;
    profile.total_clusters = total_clusters;
    profile.bounding_radius = bounding_radius;

    // Divide os clusters em páginas
    uint32_t page_count = (total_clusters + m_clusters_per_page - 1) / m_clusters_per_page;
    if (page_count == 0) page_count = 1;

    for (uint32_t p = 0; p < page_count; ++p) {
        uint32_t offset = p * m_clusters_per_page;
        uint32_t count = std::min(m_clusters_per_page, total_clusters - offset);
        bool is_root = (p == 0); // Página 0 é a raiz (sempre residente na GPU)
        size_t byte_size = size_t(count) * 96; // 96 bytes por GPUCluster

        uint32_t pid = ArboriaGPUMemoryManager::instance().register_page(
            mesh_handle, offset, count, is_root ? 0 : 1, byte_size, is_root
        );

        if (is_root) {
            profile.root_page_id = pid;
        }
        profile.page_ids.push_back(pid);
    }

    m_profiles[mesh_handle.to_u64()] = profile;
    return true;
}

bool ArboriaStreamingManager::unregister_mesh_streaming(Handle mesh_handle) {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_profiles.find(mesh_handle.to_u64());
    if (it == m_profiles.end()) {
        return false;
    }

    ArboriaGPUMemoryManager::instance().unregister_mesh_pages(mesh_handle);
    m_profiles.erase(it);
    return true;
}

void ArboriaStreamingManager::update(const float cam_pos[3], uint64_t current_frame) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (!m_initialized) return;

    // Obtém todas as instâncias ativas para calcular proximidade da câmera
    std::vector<GPUInstanceData> instances;
    ArboriaInstanceRegistry::instance().build_gpu_instance_buffer(instances);

    for (const auto& inst : instances) {
        float dx = inst.bounding_sphere[0] - cam_pos[0];
        float dy = inst.bounding_sphere[1] - cam_pos[1];
        float dz = inst.bounding_sphere[2] - cam_pos[2];
        float dist = std::sqrt(dx*dx + dy*dy + dz*dz);

        // Se o objeto está a menos de 40 metros, solicita carregamento de páginas de detalhe
        auto it = m_profiles.find(static_cast<uint64_t>(inst.mesh_id));
        if (it != m_profiles.end()) {
            const auto& profile = it->second;
            
            // Toca a página raiz
            ArboriaGPUMemoryManager::instance().touch_page(profile.root_page_id, current_frame);

            if (dist < 35.0f) {
                // Objeto próximo: torna residentes as páginas de maior detalhe
                for (size_t i = 1; i < profile.page_ids.size(); ++i) {
                    uint32_t pid = profile.page_ids[i];
                    ArboriaGPUMemoryManager::instance().make_page_resident(pid, current_frame);
                }
            } else if (dist > 70.0f) {
                // Objeto distante: páginas de detalhe podem ser descarregadas
                for (size_t i = 1; i < profile.page_ids.size(); ++i) {
                    uint32_t pid = profile.page_ids[i];
                    ArboriaGPUMemoryManager::instance().evict_page(pid);
                }
            }
        }
    }
}

bool ArboriaStreamingManager::is_cluster_resident(Handle mesh_handle, uint32_t cluster_id) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_profiles.find(mesh_handle.to_u64());
    if (it == m_profiles.end()) {
        return false;
    }

    uint32_t page_idx = cluster_id / m_clusters_per_page;
    if (page_idx >= it->second.page_ids.size()) {
        return false;
    }

    uint32_t pid = it->second.page_ids[page_idx];
    bool resident = ArboriaGPUMemoryManager::instance().is_page_resident(pid);
    if (!resident) {
        // Registra page fault
        ArboriaGPUMemoryManager::instance().record_page_fault();
    }
    return resident;
}

uint32_t ArboriaStreamingManager::get_fallback_cluster(Handle mesh_handle, uint32_t cluster_id) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_profiles.find(mesh_handle.to_u64());
    if (it == m_profiles.end()) {
        return 0;
    }

    // A página raiz (clusters 0 a m_clusters_per_page - 1) está sempre garantida na GPU
    if (it->second.total_clusters > 0) {
        return cluster_id % std::min(m_clusters_per_page, it->second.total_clusters);
    }
    return 0;
}

StreamingTelemetry ArboriaStreamingManager::get_telemetry() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto mem_stats = ArboriaGPUMemoryManager::instance().get_statistics();

    StreamingTelemetry tel{};
    tel.total_pages = mem_stats.total_pages;
    tel.resident_pages = mem_stats.resident_pages;
    tel.active_requests = 0;
    tel.total_page_faults = mem_stats.page_faults;
    tel.total_evictions = mem_stats.evictions_count;
    tel.resident_vram_bytes = mem_stats.resident_bytes;
    tel.budget_vram_bytes = mem_stats.budget_bytes;
    tel.under_budget = (mem_stats.resident_bytes <= mem_stats.budget_bytes);

    return tel;
}

} // namespace Arboria
