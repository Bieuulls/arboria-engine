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

// ============================================================================
// Gate 08 — Entrada da Tabela de Páginas Virtual
// ============================================================================
struct VGPageTableEntry {
    uint32_t virtual_page = 0;      // Número da página virtual
    uint32_t physical_frame = 0;    // Número do quadro físico (0 = não mapeado)
    bool valid = false;             // Bit de válido
    bool dirty = false;             // Bit de sujo (modificado)
    bool referenced = false;        // Bit de referência (algoritmo do relógio/LRU)
    uint64_t last_access_frame = 0; // Último frame de acesso
    uint32_t pin_count = 0;         // Contador de travamento (>0 bloqueia evicção)
};

// ============================================================================
// Gate 08 — Tabela de Páginas Virtual com Cache TLB
// ============================================================================
class VGPageTable {
public:
    VGPageTable() = default;
    ~VGPageTable() = default;

    // Traduz página virtual para quadro físico (consulta TLB, depois page table walk)
    bool translate(uint32_t virtual_page, uint32_t& physical_frame) const;

    // Mapeia página virtual para quadro físico
    void map(uint32_t virtual_page, uint32_t physical_frame);

    // Desmapeia uma página virtual
    void unmap(uint32_t virtual_page);

    // Marca página como suja / referenciada
    void set_dirty(uint32_t virtual_page);
    void set_referenced(uint32_t virtual_page, uint64_t current_frame);

    // Limpa bit de referência (para algoritmo do relógio)
    void clear_referenced(uint32_t virtual_page);

    // Trava / destrava página (evicção bloqueada enquanto pinada)
    void pin(uint32_t virtual_page);
    void unpin(uint32_t virtual_page);
    bool is_pinned(uint32_t virtual_page) const;

    size_t entry_count() const;
    bool is_mapped(uint32_t virtual_page) const;
    void clear();

private:
    mutable std::mutex m_mutex;
    std::unordered_map<uint32_t, VGPageTableEntry> m_entries;

    // TLB simples com 16 entradas (cache de traduções recentes)
    struct TLBEntry {
        uint32_t virtual_page = 0;
        uint32_t physical_frame = 0;
        bool valid = false;
    };
    static constexpr size_t TLB_SIZE = 16;
    mutable TLBEntry m_tlb[TLB_SIZE] = {};
    mutable size_t m_tlb_index = 0;

    void tlb_invalidate(uint32_t virtual_page) const;
    void tlb_insert(uint32_t virtual_page, uint32_t physical_frame) const;
};

// ============================================================================
// Gate 08 — Lista LRU com O(1) para move-to-front e evicção
// ============================================================================
struct LRUNode {
    uint32_t page_id = 0;
    LRUNode* prev = nullptr;
    LRUNode* next = nullptr;
};

class LRUList {
public:
    LRUList() = default;
    ~LRUList() { clear(); }

    // Coloca página na frente (mais recentemente usada)
    void push_front(uint32_t page_id);

    // Remove página da lista
    void erase(uint32_t page_id);

    // Remove e retorna a página menos recentemente usada (fim da lista)
    uint32_t pop_back();

    bool empty() const { return m_nodes.empty(); }
    bool contains(uint32_t page_id) const { return m_nodes.find(page_id) != m_nodes.end(); }
    size_t size() const { return m_nodes.size(); }
    void clear();

private:
    LRUNode* m_head = nullptr;
    LRUNode* m_tail = nullptr;
    std::unordered_map<uint32_t, LRUNode*> m_nodes;

    void detach(LRUNode* node);
    void attach_front(LRUNode* node);
};

// ============================================================================
// Gate 08 — Página de Geometria Aprimorada
// ============================================================================
struct GeometryPage {
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

    // Gate 08 aprimoramentos
    uint32_t gpu_virtual_address = 0;  // Endereço virtual alocado na GPU
    bool compressed = false;           // Página comprimida na memória GPU
    uint32_t pin_count = 0;            // Travamento (impede evicção enquanto > 0)
};

// Compatibilidade: GeometryPageInfo é alias para GeometryPage
using GeometryPageInfo = GeometryPage;

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

    // Gestão de residência e eviction LRU (aprimorada com VGPageTable + LRUList)
    bool make_page_resident(uint32_t page_id, uint64_t current_frame);
    bool evict_page(uint32_t page_id);
    uint32_t evict_lru_until_fits(size_t required_bytes, uint64_t current_frame);

    void touch_page(uint32_t page_id, uint64_t current_frame);
    bool is_page_resident(uint32_t page_id) const;
    const GeometryPageInfo* get_page_info(uint32_t page_id) const;

    // Operações da tabela de páginas virtual (Gate 08)
    bool translate_page(uint32_t virtual_page, uint32_t& physical_frame) const;
    void map_page(uint32_t virtual_page, uint32_t physical_frame);
    void unmap_page(uint32_t virtual_page);
    void pin_page(uint32_t page_id);
    void unpin_page(uint32_t page_id);
    bool is_page_pinned(uint32_t page_id) const;

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

    // Tabela de páginas virtual e lista LRU aprimorada (Gate 08)
    VGPageTable m_page_table;
    LRUList m_lru_list;
    std::unordered_map<uint32_t, GeometryPageInfo> m_pages;
};

} // namespace Arboria

#endif // ARBORIA_MEMORY_MANAGER_H
