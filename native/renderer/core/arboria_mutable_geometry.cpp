#include "arboria_mutable_geometry.h"
#include <cmath>
#include <algorithm>

namespace Arboria {

MutableGeometryOverlay::MutableGeometryOverlay(uint32_t instance_id, uint32_t mesh_id)
    : m_instance_id(instance_id), m_mesh_id(mesh_id), m_geometry_version(1), m_dirty_flags(MUTABLE_DIRTY_NONE)
{
}

MutableRegion& MutableGeometryOverlay::get_or_create_region(uint32_t region_id) {
    auto it = m_regions.find(region_id);
    if (it != m_regions.end()) {
        return it->second;
    }

    MutableRegion new_region;
    new_region.region_id = region_id;
    new_region.mesh_id = m_mesh_id;
    new_region.instance_id = m_instance_id;
    new_region.geometry_version = m_geometry_version;
    new_region.dirty_flags = MUTABLE_DIRTY_GEOMETRY | MUTABLE_DIRTY_DAG | MUTABLE_DIRTY_BOUNDS | MUTABLE_DIRTY_GPU_SYNC;

    auto res = m_regions.emplace(region_id, std::move(new_region));
    mark_dirty(MUTABLE_DIRTY_GEOMETRY | MUTABLE_DIRTY_BOUNDS);
    return res.first->second;
}

const MutableRegion* MutableGeometryOverlay::get_region(uint32_t region_id) const {
    auto it = m_regions.find(region_id);
    if (it != m_regions.end()) {
        return &it->second;
    }
    return nullptr;
}

bool MutableGeometryOverlay::remove_region(uint32_t region_id) {
    auto it = m_regions.find(region_id);
    if (it == m_regions.end()) {
        return false;
    }

    // Remove referências de clusters substituídos por esta região
    for (auto map_it = m_cluster_replacements.begin(); map_it != m_cluster_replacements.end(); ) {
        if (map_it->second.region_id == region_id) {
            map_it = m_cluster_replacements.erase(map_it);
        } else {
            ++map_it;
        }
    }

    m_regions.erase(it);
    bump_version();
    mark_dirty(MUTABLE_DIRTY_GEOMETRY | MUTABLE_DIRTY_DAG | MUTABLE_DIRTY_BOUNDS | MUTABLE_DIRTY_GPU_SYNC);
    return true;
}

bool MutableGeometryOverlay::is_cluster_replaced(uint32_t original_cluster_id) const {
    return m_cluster_replacements.find(original_cluster_id) != m_cluster_replacements.end();
}

const Cluster* MutableGeometryOverlay::get_replacement_cluster(uint32_t original_cluster_id) const {
    auto it = m_cluster_replacements.find(original_cluster_id);
    if (it == m_cluster_replacements.end()) {
        return nullptr;
    }

    const MutableRegion* reg = get_region(it->second.region_id);
    if (!reg || it->second.local_cluster_idx >= reg->clusters.size()) {
        return nullptr;
    }

    return &reg->clusters[it->second.local_cluster_idx];
}

const GPUCluster* MutableGeometryOverlay::get_replacement_gpu_cluster(uint32_t original_cluster_id) const {
    auto it = m_cluster_replacements.find(original_cluster_id);
    if (it == m_cluster_replacements.end()) {
        return nullptr;
    }

    const MutableRegion* reg = get_region(it->second.region_id);
    if (!reg || it->second.local_cluster_idx >= reg->gpu_clusters.size()) {
        return nullptr;
    }

    return &reg->gpu_clusters[it->second.local_cluster_idx];
}

void MutableGeometryOverlay::map_cluster_replacement(uint32_t original_cluster_id, uint32_t region_id, uint32_t local_cluster_idx) {
    m_cluster_replacements[original_cluster_id] = { region_id, local_cluster_idx };
    mark_dirty(MUTABLE_DIRTY_DAG | MUTABLE_DIRTY_GPU_SYNC);
}

void MutableGeometryOverlay::mark_dirty(uint32_t flags) {
    m_dirty_flags |= flags;
}

void MutableGeometryOverlay::clear_dirty(uint32_t flags) {
    m_dirty_flags &= ~flags;
}

void MutableGeometryOverlay::bump_version() {
    m_geometry_version++;
    for (auto& pair : m_regions) {
        pair.second.geometry_version = m_geometry_version;
    }
}

void MutableGeometryOverlay::compute_combined_bounds(
    const float original_center[3], float original_radius,
    const float original_min[3], const float original_max[3],
    float out_center[3], float& out_radius,
    float out_min[3], float out_max[3]
) const {
    if (m_regions.empty()) {
        out_center[0] = original_center[0];
        out_center[1] = original_center[1];
        out_center[2] = original_center[2];
        out_radius = original_radius;
        out_min[0] = original_min[0];
        out_min[1] = original_min[1];
        out_min[2] = original_min[2];
        out_max[0] = original_max[0];
        out_max[1] = original_max[1];
        out_max[2] = original_max[2];
        return;
    }

    // Inicializa com a AABB original
    out_min[0] = original_min[0];
    out_min[1] = original_min[1];
    out_min[2] = original_min[2];
    out_max[0] = original_max[0];
    out_max[1] = original_max[1];
    out_max[2] = original_max[2];

    // Expande com todas as regiões modificadas do overlay
    for (const auto& pair : m_regions) {
        const auto& reg = pair.second;
        if (reg.radius <= 0.0f && reg.aabb_min[0] == 0.0f && reg.aabb_max[0] == 0.0f) {
            continue;
        }

        out_min[0] = std::min(out_min[0], reg.aabb_min[0]);
        out_min[1] = std::min(out_min[1], reg.aabb_min[1]);
        out_min[2] = std::min(out_min[2], reg.aabb_min[2]);

        out_max[0] = std::max(out_max[0], reg.aabb_max[0]);
        out_max[1] = std::max(out_max[1], reg.aabb_max[1]);
        out_max[2] = std::max(out_max[2], reg.aabb_max[2]);
    }

    // Recalcula centro e raio da esfera delimitadora a partir da AABB combinada
    out_center[0] = (out_min[0] + out_max[0]) * 0.5f;
    out_center[1] = (out_min[1] + out_max[1]) * 0.5f;
    out_center[2] = (out_min[2] + out_max[2]) * 0.5f;

    float dx = out_max[0] - out_center[0];
    float dy = out_max[1] - out_center[1];
    float dz = out_max[2] - out_center[2];
    out_radius = std::sqrt(dx*dx + dy*dy + dz*dz);
}

void MutableGeometryOverlay::clear() {
    m_regions.clear();
    m_cluster_replacements.clear();
    m_dirty_flags = MUTABLE_DIRTY_NONE;
    bump_version();
}

} // namespace Arboria
