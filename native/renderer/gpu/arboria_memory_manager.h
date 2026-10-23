#ifndef ARBORIA_MEMORY_MANAGER_H
#define ARBORIA_MEMORY_MANAGER_H

#include "../core/arboria_types.h"
#include "../core/arboria_handle.h"
#include <cstdint>
#include <vector>
#include <unordered_map>
#include <string>
#include <mutex>
#include <algorithm>

namespace Arboria {

enum class PageState : uint8_t {
    UNLOADED = 0,
    REQUESTED = 1,
    UPLOADING = 2,
    RESIDENT = 3,
    EVICTED = 4
};

struct GeometryPageInfo {
    uint32_t page_id = 0;
    Handle mesh_handle;
    uint32_t cluster_offset = 0;
    uint32_t cluster_count = 0;
    uint32_t lod_level = 0;
    size_t byte_size = 0;
    bool is_root = false;
    PageState state = PageState::UNLOADED;
    uint64_t last_access_frame = 0;
    float priority = 0.0f;
};

struct GPUMemoryStats {
    size_t budget_bytes = 0;
    size_t allocated_bytes = 0;
    size_t resident_bytes = 0;
    size_t peak_resident_bytes = 0;
    uint32_t total_pages = 0;
    uint32_t resident_pages = 0;
    uint32_t page_faults = 0;
    uint32_t evictions_count = 0;
    uint32_t pool_reused_count = 0;
};

class ARBORIA_CLASS ArboriaGPUMemoryManager {
public:
    static ArboriaGPUMemoryManager& instance();

    void initialize(size_t default_budget_bytes = 128 * 1024 * 1024); // 128 MB default
    void shutdown();

    void set_budget(size_t bytes);
    size_t get_budget() const;

    // Registro e ciclo de vida de páginas de geometria
    uint32_t register_page(Handle mesh_handle, uint32_t cluster_offset, uint32_t cluster_count,
                           uint32_t lod_level, size_t byte_size, bool is_root);
    bool unregister_page(uint32_t page_id);
    void unregister_mesh_pages(Handle mesh_handle);

    // Gestão de residência e eviction LRU
    bool make_page_resident(uint32_t page_id, uint64_t current_frame);
    bool evict_page(uint32_t page_id);
    uint32_t evict_lru_until_fits(size_t required_bytes, uint64_t current_frame);

    void touch_page(uint32_t page_id, uint64_t current_frame);
    bool is_page_resident(uint32_t page_id) const;
    const GeometryPageInfo* get_page_info(uint32_t page_id) const;

    // Telemetria precisa de VRAM
    GPUMemoryStats get_statistics() const;
    void record_page_fault();
    void record_pool_reuse();

    void reset_counters();

private:
    ArboriaGPUMemoryManager() = default;
    ~ArboriaGPUMemoryManager() = default;

    mutable std::mutex m_mutex;
    bool m_initialized = false;
    size_t m_budget_bytes = 128 * 1024 * 1024;
    size_t m_allocated_bytes = 0;
    size_t m_resident_bytes = 0;
    size_t m_peak_resident_bytes = 0;
    uint32_t m_next_page_id = 1;

    uint32_t m_page_faults = 0;
    uint32_t m_evictions_count = 0;
    uint32_t m_pool_reused_count = 0;

    std::unordered_map<uint32_t, GeometryPageInfo> m_pages;
};

} // namespace Arboria

#endif // ARBORIA_MEMORY_MANAGER_H
