#include "arboria_memory_manager.h"
#include "../core/arboria_logger.h"
#include <algorithm>

namespace Arboria {

// ============================================================================
// VGPageTable — Tabela de Páginas Virtual com Cache TLB
// ============================================================================

bool VGPageTable::translate(uint32_t virtual_page, uint32_t& physical_frame) const {
    std::lock_guard<std::mutex> lock(m_mutex);

    // Consulta TLB primeiro
    for (size_t i = 0; i < TLB_SIZE; ++i) {
        if (m_tlb[i].valid && m_tlb[i].virtual_page == virtual_page) {
            physical_frame = m_tlb[i].physical_frame;
            return true;
        }
    }

    // Page table walk
    auto it = m_entries.find(virtual_page);
    if (it != m_entries.end() && it->second.valid) {
        physical_frame = it->second.physical_frame;
        tlb_insert(virtual_page, physical_frame);
        return true;
    }

    return false;
}

void VGPageTable::map(uint32_t virtual_page, uint32_t physical_frame) {
    std::lock_guard<std::mutex> lock(m_mutex);

    auto& entry = m_entries[virtual_page];
    entry.virtual_page = virtual_page;
    entry.physical_frame = physical_frame;
    entry.valid = true;

    tlb_insert(virtual_page, physical_frame);
}

void VGPageTable::unmap(uint32_t virtual_page) {
    std::lock_guard<std::mutex> lock(m_mutex);

    auto it = m_entries.find(virtual_page);
    if (it != m_entries.end()) {
        it->second.valid = false;
        tlb_invalidate(virtual_page);
    }
}

void VGPageTable::set_dirty(uint32_t virtual_page) {
    std::lock_guard<std::mutex> lock(m_mutex);

    auto it = m_entries.find(virtual_page);
    if (it != m_entries.end()) {
        it->second.dirty = true;
    }
}

void VGPageTable::set_referenced(uint32_t virtual_page, uint64_t current_frame) {
    std::lock_guard<std::mutex> lock(m_mutex);

    auto it = m_entries.find(virtual_page);
    if (it != m_entries.end()) {
        it->second.referenced = true;
        it->second.last_access_frame = current_frame;
    }
}

void VGPageTable::clear_referenced(uint32_t virtual_page) {
    std::lock_guard<std::mutex> lock(m_mutex);

    auto it = m_entries.find(virtual_page);
    if (it != m_entries.end()) {
        it->second.referenced = false;
    }
}

void VGPageTable::pin(uint32_t virtual_page) {
    std::lock_guard<std::mutex> lock(m_mutex);

    auto it = m_entries.find(virtual_page);
    if (it != m_entries.end()) {
        ++it->second.pin_count;
    }
}

void VGPageTable::unpin(uint32_t virtual_page) {
    std::lock_guard<std::mutex> lock(m_mutex);

    auto it = m_entries.find(virtual_page);
    if (it != m_entries.end() && it->second.pin_count > 0) {
        --it->second.pin_count;
    }
}

bool VGPageTable::is_pinned(uint32_t virtual_page) const {
    std::lock_guard<std::mutex> lock(m_mutex);

    auto it = m_entries.find(virtual_page);
    if (it != m_entries.end()) {
        return it->second.pin_count > 0;
    }
    return false;
}

size_t VGPageTable::entry_count() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_entries.size();
}

bool VGPageTable::is_mapped(uint32_t virtual_page) const {
    std::lock_guard<std::mutex> lock(m_mutex);

    auto it = m_entries.find(virtual_page);
    return (it != m_entries.end() && it->second.valid);
}

void VGPageTable::clear() {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_entries.clear();
    for (size_t i = 0; i < TLB_SIZE; ++i) {
        m_tlb[i] = TLBEntry{};
    }
    m_tlb_index = 0;
}

void VGPageTable::tlb_invalidate(uint32_t virtual_page) const {
    for (size_t i = 0; i < TLB_SIZE; ++i) {
        if (m_tlb[i].valid && m_tlb[i].virtual_page == virtual_page) {
            m_tlb[i] = TLBEntry{};
            break;
        }
    }
}

void VGPageTable::tlb_insert(uint32_t virtual_page, uint32_t physical_frame) const {
    m_tlb[m_tlb_index] = TLBEntry{virtual_page, physical_frame, true};
    m_tlb_index = (m_tlb_index + 1) % TLB_SIZE;
}

// ============================================================================
// LRUList — Lista LRU Duplamente Encadeada com O(1)
// ============================================================================

void LRUList::push_front(uint32_t page_id) {
    // Se já existe, move para frente
    auto it = m_nodes.find(page_id);
    if (it != m_nodes.end()) {
        detach(it->second);
        attach_front(it->second);
        return;
    }

    LRUNode* node = new LRUNode{page_id, nullptr, nullptr};
    attach_front(node);
    m_nodes[page_id] = node;
}

void LRUList::erase(uint32_t page_id) {
    auto it = m_nodes.find(page_id);
    if (it == m_nodes.end()) return;

    detach(it->second);
    delete it->second;
    m_nodes.erase(it);
}

uint32_t LRUList::pop_back() {
    if (!m_tail) return 0;

    LRUNode* node = m_tail;
    uint32_t page_id = node->page_id;
    detach(node);
    delete node;
    m_nodes.erase(page_id);
    return page_id;
}

void LRUList::clear() {
    while (m_head) {
        LRUNode* next = m_head->next;
        delete m_head;
        m_head = next;
    }
    m_tail = nullptr;
    m_nodes.clear();
}

void LRUList::detach(LRUNode* node) {
    if (node->prev) node->prev->next = node->next;
    else m_head = node->next;

    if (node->next) node->next->prev = node->prev;
    else m_tail = node->prev;

    node->prev = nullptr;
    node->next = nullptr;
}

void LRUList::attach_front(LRUNode* node) {
    node->next = m_head;
    node->prev = nullptr;
    if (m_head) m_head->prev = node;
    m_head = node;
    if (!m_tail) m_tail = node;
}

// ============================================================================
// ArboriaGPUMemoryManager — Gerenciador de Memória GPU Aprimorado (Gate 08)
// ============================================================================

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
    m_page_table.clear();
    m_lru_list.clear();
    m_initialized = true;
    ARBORIA_LOG_INFO("[ArboriaGPUMemoryManager] Inicializado com orcamento de VRAM: " +
                     std::to_string(m_budget_bytes / (1024 * 1024)) + " MB.");
}

void ArboriaGPUMemoryManager::shutdown() {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_pages.clear();
    m_page_table.clear();
    m_lru_list.clear();
    m_allocated_bytes = 0;
    m_resident_bytes = 0;
    m_initialized = false;
    ARBORIA_LOG_INFO("[ArboriaGPUMemoryManager] Finalizado com sucesso. Memoria liberada.");
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
    info.gpu_virtual_address = page_id;  // Endereço virtual simplificado = page_id
    info.compressed = false;
    info.pin_count = 0;

    m_allocated_bytes += byte_size;
    if (is_root) {
        m_resident_bytes += byte_size;
        if (m_resident_bytes > m_peak_resident_bytes) {
            m_peak_resident_bytes = m_resident_bytes;
        }
    }

    // Mapeia na tabela de páginas virtual
    m_page_table.map(page_id, page_id);

    // Adiciona páginas não-raiz à lista LRU
    if (!is_root) {
        m_lru_list.push_front(page_id);
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

    m_lru_list.erase(page_id);
    m_page_table.unmap(page_id);
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
            m_lru_list.erase(pid);
            m_page_table.unmap(pid);
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
        m_lru_list.push_front(page_id);
        m_page_table.set_referenced(page_id, current_frame);
        return true;
    }

    // Se a página está travada (pinada), não pode ser tornada residente via evicção forçada
    // Mas ainda assim pode ser alocada se houver espaço — o pin bloqueia apenas evicção
    if (it->second.pin_count > 0 && !it->second.is_root) {
        // Página pinada não-raiz: ainda pode ser residente, mas não será evictada
    }

    // Se a página excede o orçamento restante, descarrega páginas LRU não-raiz e não-pinadas
    if (m_resident_bytes + it->second.byte_size > m_budget_bytes) {
        size_t needed = (m_resident_bytes + it->second.byte_size) - m_budget_bytes;

        // Evicção via lista LRU (O(1) por página)
        size_t freed = 0;
        while (!m_lru_list.empty() && freed < needed) {
            uint32_t lru_id = m_lru_list.pop_back();
            auto& cinfo = m_pages[lru_id];
            if (cinfo.state == PageState::RESIDENT && cinfo.pin_count == 0 && !cinfo.is_root) {
                cinfo.state = PageState::EVICTED;
                freed += cinfo.byte_size;
                if (m_resident_bytes >= cinfo.byte_size) {
                    m_resident_bytes -= cinfo.byte_size;
                }
                m_page_table.unmap(lru_id);
                m_evictions_count++;
            }
        }
    }

    it->second.state = PageState::RESIDENT;
    it->second.last_access_frame = current_frame;
    m_resident_bytes += it->second.byte_size;
    if (m_resident_bytes > m_peak_resident_bytes) {
        m_peak_resident_bytes = m_resident_bytes;
    }

    m_lru_list.push_front(page_id);
    m_page_table.map(page_id, page_id);
    m_page_table.set_referenced(page_id, current_frame);

    return true;
}

bool ArboriaGPUMemoryManager::evict_page(uint32_t page_id) {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_pages.find(page_id);
    if (it == m_pages.end()) {
        return false;
    }

    if (it->second.is_root) {
        // Páginas raiz são obrigadas a permanecer residentes
        return false;
    }

    if (it->second.pin_count > 0) {
        // Página travada não pode ser evictada
        return false;
    }

    if (it->second.state == PageState::RESIDENT) {
        it->second.state = PageState::EVICTED;
        if (m_resident_bytes >= it->second.byte_size) {
            m_resident_bytes -= it->second.byte_size;
        } else {
            m_resident_bytes = 0;
        }
        m_lru_list.erase(page_id);
        m_page_table.unmap(page_id);
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
    uint32_t count = 0;
    size_t freed = 0;

    while (!m_lru_list.empty() && freed < needed) {
        uint32_t lru_id = m_lru_list.pop_back();
        auto& cinfo = m_pages[lru_id];
        if (cinfo.state == PageState::RESIDENT && cinfo.pin_count == 0 && !cinfo.is_root) {
            cinfo.state = PageState::EVICTED;
            freed += cinfo.byte_size;
            if (m_resident_bytes >= cinfo.byte_size) {
                m_resident_bytes -= cinfo.byte_size;
            }
            m_page_table.unmap(lru_id);
            m_evictions_count++;
            count++;
        }
    }

    return count;
}

void ArboriaGPUMemoryManager::touch_page(uint32_t page_id, uint64_t current_frame) {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_pages.find(page_id);
    if (it != m_pages.end()) {
        it->second.last_access_frame = current_frame;
        m_lru_list.push_front(page_id);
        m_page_table.set_referenced(page_id, current_frame);
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

// Gate 08 — Operações da tabela de páginas virtual
bool ArboriaGPUMemoryManager::translate_page(uint32_t virtual_page, uint32_t& physical_frame) const {
    return m_page_table.translate(virtual_page, physical_frame);
}

void ArboriaGPUMemoryManager::map_page(uint32_t virtual_page, uint32_t physical_frame) {
    m_page_table.map(virtual_page, physical_frame);
}

void ArboriaGPUMemoryManager::unmap_page(uint32_t virtual_page) {
    m_page_table.unmap(virtual_page);
}

void ArboriaGPUMemoryManager::pin_page(uint32_t page_id) {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_pages.find(page_id);
    if (it != m_pages.end()) {
        ++it->second.pin_count;
        m_page_table.pin(page_id);
    }
}

void ArboriaGPUMemoryManager::unpin_page(uint32_t page_id) {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_pages.find(page_id);
    if (it != m_pages.end() && it->second.pin_count > 0) {
        --it->second.pin_count;
        m_page_table.unpin(page_id);
    }
}

bool ArboriaGPUMemoryManager::is_page_pinned(uint32_t page_id) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_pages.find(page_id);
    if (it != m_pages.end()) {
        return it->second.pin_count > 0;
    }
    return false;
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
