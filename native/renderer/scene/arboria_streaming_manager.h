#ifndef ARBORIA_STREAMING_MANAGER_H
#define ARBORIA_STREAMING_MANAGER_H

#include "../core/arboria_types.h"
#include "../core/arboria_handle.h"
#include "../core/arboria_error.h"
#include "../gpu/arboria_memory_manager.h"
#include <cstdint>
#include <vector>
#include <unordered_map>
#include <string>
#include <mutex>

namespace Arboria {

struct MeshStreamingProfile {
    Handle mesh_handle;
    uint32_t total_clusters = 0;
    uint32_t root_page_id = 0;
    std::vector<uint32_t> page_ids;
    float bounding_radius = 1.0f;
};

struct StreamingTelemetry {
    uint32_t total_pages = 0;
    uint32_t resident_pages = 0;
    uint32_t active_requests = 0;
    uint32_t total_page_faults = 0;
    uint32_t total_evictions = 0;
    size_t resident_vram_bytes = 0;
    size_t budget_vram_bytes = 0;
    bool under_budget = true;
};

class ARBORIA_CLASS ArboriaStreamingManager {
public:
    static ArboriaStreamingManager& instance();

    void initialize(size_t vram_budget_bytes = 128 * 1024 * 1024);
    void shutdown();

    // Particiona e registra uma malha no pipeline de streaming
    Status register_mesh_streaming(Handle mesh_handle, uint32_t total_clusters, float bounding_radius);
    Status unregister_mesh_streaming(Handle mesh_handle);

    // Atualização de streaming baseada na posição da câmera
    void update(const float cam_pos[3], uint64_t current_frame);

    // Consulta de residência e fallback de clusters
    bool is_cluster_resident(Handle mesh_handle, uint32_t cluster_id) const;
    uint32_t get_fallback_cluster(Handle mesh_handle, uint32_t cluster_id) const;

    // Acessores de telemetria
    StreamingTelemetry get_telemetry() const;
    void set_vram_budget(size_t bytes);

private:
    ArboriaStreamingManager() = default;
    ~ArboriaStreamingManager() = default;

    mutable std::mutex m_mutex;
    bool m_initialized = false;
    std::unordered_map<uint32_t, MeshStreamingProfile> m_profiles;  // key: mesh_handle.index
    uint32_t m_clusters_per_page = 64;

    // Throttling: streaming roda a cada m_throttle_interval frames
    uint64_t m_last_streaming_frame = 0;
    uint64_t m_throttle_interval = 4; // Atualiza a cada 4 frames por default
};

} // namespace Arboria

#endif // ARBORIA_STREAMING_MANAGER_H
