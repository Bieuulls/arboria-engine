#include "arboria_material_table.h"

namespace Arboria {

ArboriaMaterialTable& ArboriaMaterialTable::instance() {
    static ArboriaMaterialTable s_inst;
    return s_inst;
}

ArboriaMaterialTable::ArboriaMaterialTable() {
    // Material default index 0
    m_materials.push_back(MaterialRecord{});
}

uint32_t ArboriaMaterialTable::register_material(const MaterialRecord& record) {
    std::lock_guard<std::mutex> lock(m_mutex);
    uint32_t id = static_cast<uint32_t>(m_materials.size());
    m_materials.push_back(record);
    return id;
}

bool ArboriaMaterialTable::update_material(uint32_t material_id, const MaterialRecord& record) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (material_id >= m_materials.size()) return false;
    m_materials[material_id] = record;
    return true;
}

const MaterialRecord* ArboriaMaterialTable::get_material(uint32_t material_id) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (material_id >= m_materials.size()) return nullptr;
    return &m_materials[material_id];
}

size_t ArboriaMaterialTable::get_material_count() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_materials.size();
}

void ArboriaMaterialTable::clear() {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_materials.clear();
    m_materials.push_back(MaterialRecord{});
}

} // namespace Arboria
