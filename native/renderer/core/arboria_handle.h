#ifndef ARBORIA_HANDLE_H
#define ARBORIA_HANDLE_H

#include <cstdint>
#include <vector>

namespace Arboria {

// Handle de 64 bits com controle estrito de geracao (32-bit geracao + 32-bit indice)
struct Handle {
    uint32_t index = 0;      // Indice 1-based no pool (0 = invalido)
    uint32_t generation = 0; // Contador de geracao (incrementado a cada reciclagem)

    constexpr Handle() = default;
    constexpr Handle(uint32_t p_index, uint32_t p_generation)
        : index(p_index), generation(p_generation) {}
    constexpr Handle(uint64_t val)
        : index(static_cast<uint32_t>(val & 0xFFFFFFFFULL)),
          generation(static_cast<uint32_t>(val >> 32)) {}

    constexpr bool is_valid() const {
        return index != 0 && generation != 0;
    }

    constexpr uint64_t to_u64() const {
        return (static_cast<uint64_t>(generation) << 32) | static_cast<uint64_t>(index);
    }

    constexpr operator uint64_t() const {
        return to_u64();
    }

    static constexpr Handle from_u64(uint64_t val) {
        return Handle(val);
    }

    bool operator==(const Handle& other) const {
        return index == other.index && generation == other.generation;
    }

    bool operator!=(const Handle& other) const {
        return !(*this == other);
    }
};

// Pool Geracional com alocacao O(1) e rejeicao automatica de handles obsoletos
template <typename T>
class GenerationalPool {
public:
    struct Slot {
        T data{};
        uint32_t generation = 1;
        bool active = false;
    };

    Handle allocate(const T& item) {
        uint32_t idx = 0;
        if (!m_free_list.empty()) {
            idx = m_free_list.back();
            m_free_list.pop_back();
        } else {
            m_slots.emplace_back();
            idx = static_cast<uint32_t>(m_slots.size()); // 1-based
        }

        Slot& slot = m_slots[idx - 1];
        slot.data = item;
        slot.active = true;
        return Handle{ idx, slot.generation };
    }

    bool release(Handle h) {
        if (!is_valid(h)) return false;
        Slot& slot = m_slots[h.index - 1];
        slot.active = false;
        slot.generation++;
        if (slot.generation == 0) slot.generation = 1; // previne geracao zero
        slot.data = T{};
        m_free_list.push_back(h.index);
        return true;
    }

    bool is_valid(Handle h) const {
        if (h.index == 0 || h.index > m_slots.size()) return false;
        const Slot& slot = m_slots[h.index - 1];
        return slot.active && slot.generation == h.generation;
    }

    T* get(Handle h) {
        if (!is_valid(h)) return nullptr;
        return &m_slots[h.index - 1].data;
    }

    const T* get(Handle h) const {
        if (!is_valid(h)) return nullptr;
        return &m_slots[h.index - 1].data;
    }

    T* get_by_index(uint32_t idx) {
        if (idx == 0 || idx > m_slots.size()) return nullptr;
        Slot& slot = m_slots[idx - 1];
        return slot.active ? &slot.data : nullptr;
    }

    const T* get_by_index(uint32_t idx) const {
        if (idx == 0 || idx > m_slots.size()) return nullptr;
        const Slot& slot = m_slots[idx - 1];
        return slot.active ? &slot.data : nullptr;
    }

    size_t active_count() const {
        return m_slots.size() - m_free_list.size();
    }

    size_t capacity() const {
        return m_slots.size();
    }

    void clear() {
        m_slots.clear();
        m_free_list.clear();
    }

    std::vector<Slot>& get_slots() { return m_slots; }
    const std::vector<Slot>& get_slots() const { return m_slots; }

private:
    std::vector<Slot> m_slots;
    std::vector<uint32_t> m_free_list;
};

} // namespace Arboria

#endif // ARBORIA_HANDLE_H
