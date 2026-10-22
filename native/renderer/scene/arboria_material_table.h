#ifndef ARBORIA_MATERIAL_TABLE_H
#define ARBORIA_MATERIAL_TABLE_H

#include "../core/arboria_types.h"
#include <vector>
#include <cstdint>
#include <mutex>

namespace Arboria {

struct MaterialRecord {
    float albedo[4] = { 0.8f, 0.82f, 0.85f, 1.0f };
    float roughness = 0.5f;
    float metallic = 0.0f;
    float specular = 0.5f;
    float alpha_cutoff = 0.5f;
    float uv_scale[2] = { 1.0f, 1.0f };
    float normal_scale = 1.0f;
    uint32_t flags = 0; // bit 0: alpha_cutout, bit 1: double_sided
};

class ARBORIA_CLASS ArboriaMaterialTable {
public:
    static ArboriaMaterialTable& instance();

    uint32_t register_material(const MaterialRecord& record);
    bool update_material(uint32_t material_id, const MaterialRecord& record);
    const MaterialRecord* get_material(uint32_t material_id) const;

    size_t get_material_count() const;
    void clear();

private:
    ArboriaMaterialTable();
    ~ArboriaMaterialTable() = default;

    mutable std::mutex m_mutex;
    std::vector<MaterialRecord> m_materials;
};

} // namespace Arboria

#endif // ARBORIA_MATERIAL_TABLE_H
