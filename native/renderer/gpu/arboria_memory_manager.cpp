#include "arboria_memory_manager.h"
#include <iostream>
#include <algorithm>

namespace Arboria {

ArboriaGPUMemoryManager& ArboriaGPUMemoryManager::instance() {
    static ArboriaGPUMemoryManager s_instance;
    return s_instance;
}

void ArboriaGPUMemoryManager::initialize(size_t default_budget_bytes) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_budget_bytes = default_budget_bytes;
    m_allocated_bytes = 0;
    m_resident_bytes = 0;
    m_peak_resident_bytes = 0;
    m_next_page_id = 1;
    m_page_faults = 0;
    m_evictions_count = 0;
    m_pool_reused_count = 0;
    m_pages.clear();
    m_initialized = true;
    std::cout << "[ArboriaGPUMemoryManager] Inicializado com orcamento de VRAM: "
              << (m_budget_bytes / (1024 * 1024)) << " MB." << std::endl;
}

void ArboriaGPUMemoryManager::shutdown() {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_pages.clear();
    m_allocated_bytes = 0;
    m_resident_bytes = 0;
    m_initialized = false;
    std::cout << "[ArboriaGPUMemoryManager] Finalizado com sucesso. Memoria liberada." << std::endl;
}

void ArboriaGPUMemoryManager::set_budget(size_t bytes) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_budget_bytes = bytes;
}

size_t ArboriaGPUMemoryManager::get_budget() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_budget_bytes;
}

uint32_t ArboriaGPUMemoryManager::register_page(
    Handle mesh_handle,
    uint32_t cluster_offset,
    uint32_t cluster_count,
    uint32_t lod_level,
    size_t byte_size,
    bool is_root
) {
    std::lock_guard<std::mutex> lock(m_mutex);
    uint32_t page_id = m_next_page_id++;

    GeometryPageInfo info{};
    info.page_id = page_id;
    info.mesh_handle = mesh_handle;
    info.cluster_offset = cluster_offset;
    info.cluster_count = cluster_count;
    info.lod_level = lod_level;
    info.byte_size = byte_size;
    info.is_root = is_root;
    info.state = is_root ? PageState::RESIDENT : PageState::UNLOADED;
    info.last_access_frame = 0;
    info.priority = is_root ? 1e9f : 0.0f;

    m_allocated_bytes += byte_size;
    if (is_root) {
        m_resident_bytes += byte_size;
        if (m_resident_bytes > m_peak_resident_bytes) {
            m_peak_resident_bytes = m_resident_bytes;
        }
    }

    m_pages[page_id] = info;
    return page_id;
}

bool ArboriaGPUMemoryManager::unregister_page(uint32_t page_id) {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_pages.find(page_id);
    if (it == m_pages.end()) {
        return false;
    }

    if (it->second.state == PageState::RESIDENT) {
        if (m_resident_bytes >= it->second.byte_size) {
            m_resident_bytes -= it->second.byte_size;
        } else {
            m_resident_bytes = 0;
        }
    }

    if (m_allocated_bytes >= it->second.byte_size) {
        m_allocated_bytes -= it->second.byte_size;
    } else {
        m_allocated_bytes = 0;
    }

    m_pages.erase(it);
    return true;
}

void ArboriaGPUMemoryManager::unregister_mesh_pages(Handle mesh_handle) {
    std::lock_guard<std::mutex> lock(m_mutex);
    std::vector<uint32_t> to_remove;
    for (const auto& kv : m_pages) {
        if (kv.second.mesh_handle == mesh_handle) {
            to_remove.push_back(kv.first);
        }
    }

    for (uint32_t pid : to_remove) {
        auto it = m_pages.find(pid);
        if (it != m_pages.end()) {
            if (it->second.state == PageState::RESIDENT) {
                if (m_resident_bytes >= it->second.byte_size) {
                    m_resident_bytes -= it->second.byte_size;
                } else {
                    m_resident_bytes = 0;
                }
            }
            if (m_allocated_bytes >= it->second.byte_size) {
                m_allocated_bytes -= it->second.byte_size;
            } else {
                m_allocated_bytes = 0;
            }
            m_pages.erase(it);
        }
    }
}

bool ArboriaGPUMemoryManager::make_page_resident(uint32_t page_id, uint64_t current_frame) {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_pages.find(page_id);
    if (it == m_pages.end()) {
        return false;
    }

    if (it->second.state == PageState::RESIDENT) {
        it->second.last_access_frame = current_frame;
        return true;
    }

    // Se a página excede o orçamento restante, descarrega páginas LRU não-raiz
    if (m_resident_bytes + it->second.byte_size > m_budget_bytes) {
        size_t needed = (m_resident_bytes + it->second.byte_size) - m_budget_bytes;
        
        // Coleta páginas não-raiz candidatas ordenadas por frame de acesso (LRU)
        std::vector<uint32_t> candidates;
        for (const auto& kv : m_pages) {
            if (kv.first != page_id && !kv.second.is_root && kv.second.state == PageState::RESIDENT) {
                candidates.push_back(kv.first);
            }
        }

        std::sort(candidates.begin(), candidates.end(), [this](uint32_t a, uint32_t b) {
            return m_pages[a].last_access_frame < m_pages[b].last_access_frame;
        });

        size_t freed = 0;
        for (uint32_t cid : candidates) {
            if (freed >= needed) break;
            auto& cinfo = m_pages[cid];
            cinfo.state = PageState::EVICTED;
            freed += cinfo.byte_size;
            if (m_resident_bytes >= cinfo.byte_size) {
                m_resident_bytes -= cinfo.byte_size;
            }
            m_evictions_count++;
        }
    }

    it->second.state = PageState::RESIDENT;
    it->second.last_access_frame = current_frame;
    m_resident_bytes += it->second.byte_size;
    if (m_resident_bytes > m_peak_resident_bytes) {
        m_peak_resident_bytes = m_resident_bytes;
    }

    return true;
}

bool ArboriaGPUMemoryManager::evict_page(uint32_t page_id) {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_pages.find(page_id);
    if (it == m_pages.end()) {
        return false;
    }

    if (it->second.is_root) {
        // Páginas raiz são obrigadas a permanecer residentes para garantir fallback contínuo
        return false;
    }

    if (it->second.state == PageState::RESIDENT) {
        it->second.state = PageState::EVICTED;
        if (m_resident_bytes >= it->second.byte_size) {
            m_resident_bytes -= it->second.byte_size;
        } else {
            m_resident_bytes = 0;
        }
        m_evictions_count++;
        return true;
    }

    return false;
}

uint32_t ArboriaGPUMemoryManager::evict_lru_until_fits(size_t required_bytes, uint64_t current_frame) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_resident_bytes + required_bytes <= m_budget_bytes) {
        return 0;
    }

    size_t needed = (m_resident_bytes + required_bytes) - m_budget_bytes;
    std::vector<uint32_t> candidates;
    for (const auto& kv : m_pages) {
        if (!kv.second.is_root && kv.second.state == PageState::RESIDENT) {
            candidates.push_back(kv.first);
        }
    }

    std::sort(candidates.begin(), candidates.end(), [this](uint32_t a, uint32_t b) {
        return m_pages[a].last_access_frame < m_pages[b].last_access_frame;
    });

    uint32_t count = 0;
    size_t freed = 0;
    for (uint32_t cid : candidates) {
        if (freed >= needed) break;
        auto& cinfo = m_pages[cid];
        cinfo.state = PageState::EVICTED;
        freed += cinfo.byte_size;
        if (m_resident_bytes >= cinfo.byte_size) {
            m_resident_bytes -= cinfo.byte_size;
        }
        m_evictions_count++;
        count++;
    }

    return count;
}

void ArboriaGPUMemoryManager::touch_page(uint32_t page_id, uint64_t current_frame) {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_pages.find(page_id);
    if (it != m_pages.end()) {
        it->second.last_access_frame = current_frame;
    }
}

bool ArboriaGPUMemoryManager::is_page_resident(uint32_t page_id) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_pages.find(page_id);
    if (it != m_pages.end()) {
        return it->second.state == PageState::RESIDENT;
    }
    return false;
}

const GeometryPageInfo* ArboriaGPUMemoryManager::get_page_info(uint32_t page_id) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_pages.find(page_id);
    if (it != m_pages.end()) {
        return &it->second;
    }
    return nullptr;
}

GPUMemoryStats ArboriaGPUMemoryManager::get_statistics() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    GPUMemoryStats stats{};
    stats.budget_bytes = m_budget_bytes;
    stats.allocated_bytes = m_allocated_bytes;
    stats.resident_bytes = m_resident_bytes;
    stats.peak_resident_bytes = m_peak_resident_bytes;
    stats.total_pages = static_cast<uint32_t>(m_pages.size());

    uint32_t resident_count = 0;
    for (const auto& kv : m_pages) {
        if (kv.second.state == PageState::RESIDENT) {
            resident_count++;
        }
    }
    stats.resident_pages = resident_count;
    stats.page_faults = m_page_faults;
    stats.evictions_count = m_evictions_count;
    stats.pool_reused_count = m_pool_reused_count;

    return stats;
}

void ArboriaGPUMemoryManager::record_page_fault() {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_page_faults++;
}

void ArboriaGPUMemoryManager::record_pool_reuse() {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_pool_reused_count++;
}

void ArboriaGPUMemoryManager::reset_counters() {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_page_faults = 0;
    m_evictions_count = 0;
    m_pool_reused_count = 0;
}

} // namespace Arboria
