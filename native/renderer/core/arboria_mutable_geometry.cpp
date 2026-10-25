#include "arboria_mutable_geometry.h"
#include "arboria_mesh_resource.h"
#include <cmath>
#include <algorithm>
#include <fstream>
#include <iomanip>
#include <cstring>
#include <filesystem>

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
    m_physics_mesh = MutablePhysicsMesh{};
    m_dirty_flags = MUTABLE_DIRTY_NONE;
    bump_version();
}

uint32_t MutableGeometryOverlay::apply_depression(
    const VGMeshResource& base_mesh,
    const float center[3],
    float radius,
    float depth,
    bool subdivide
) {
    if (!base_mesh.is_valid() || radius <= 0.0001f) {
        return 0;
    }

    const auto& lods = base_mesh.get_lods();
    const auto& clusters = base_mesh.get_clusters();
    const auto& base_vertices = base_mesh.get_vertices();
    const auto& base_indices = base_mesh.get_indices();

    // Determina intervalo de clusters do LOD 0 (nível de detalhe máximo de referência)
    uint32_t lod0_offset = 0;
    uint32_t lod0_count = static_cast<uint32_t>(clusters.size());
    if (!lods.empty()) {
        lod0_offset = lods[0].offset;
        lod0_count = lods[0].clusters;
    }

    uint32_t modified_count = 0;

    for (uint32_t i = 0; i < lod0_count; ++i) {
        uint32_t c_idx = lod0_offset + i;
        const auto& c = clusters[c_idx];

        // 1. Teste de interseção da esfera do cluster com a esfera da ferramenta
        float c_dx = c.center[0] - center[0];
        float c_dy = c.center[1] - center[1];
        float c_dz = c.center[2] - center[2];
        float dist_sq = c_dx * c_dx + c_dy * c_dy + c_dz * c_dz;
        float max_reach = c.radius + radius;

        if (dist_sq > max_reach * max_reach) {
            continue; // Cluster fora do raio de ação
        }

        // 2. Extrai ou recupera a geometria de trabalho (Copy-On-Write)
        std::vector<Vertex> work_verts;
        std::vector<uint32_t> work_indices;
        uint32_t region_id = 1000 + c_idx;

        if (is_cluster_replaced(c_idx)) {
            // Continuidade incremental: aplica sobre a geometria já modificada no overlay
            const MutableRegion* existing_reg = get_region(m_cluster_replacements[c_idx].region_id);
            if (existing_reg) {
                work_verts = existing_reg->vertices;
                work_indices = existing_reg->indices;
            }
        }

        if (work_verts.empty()) {
            // Primeira modificação deste cluster: copia estritamente do asset base compartilhado
            work_verts.resize(c.vertex_count);
            for (uint32_t v = 0; v < c.vertex_count; ++v) {
                work_verts[v] = base_vertices[c.vertex_offset + v];
            }

            work_indices.resize(c.triangle_count * 3);
            for (uint32_t t = 0; t < c.triangle_count * 3; ++t) {
                work_indices[t] = base_indices[c.triangle_offset + t];
            }
        }

        // 3. Aplica a deformação localizada aos vértices dentro do raio
        bool cluster_deformed = false;
        for (auto& v : work_verts) {
            float dx = v.position[0] - center[0];
            float dy = v.position[1] - center[1];
            float dz = v.position[2] - center[2];
            float d = std::sqrt(dx * dx + dy * dy + dz * dz);

            if (d < radius) {
                float t = d / radius;
                // Hermite suave (smoothstep): f(t) = (1 - t)^2 * (1 + 2t)
                float falloff = (1.0f - t) * (1.0f - t) * (1.0f + 2.0f * t);

                v.position[0] -= v.normal[0] * (depth * falloff);
                v.position[1] -= v.normal[1] * (depth * falloff);
                v.position[2] -= v.normal[2] * (depth * falloff);
                cluster_deformed = true;
            }
        }

        if (!cluster_deformed && !is_cluster_replaced(c_idx)) {
            continue; // Nenhum vértice dentro do raio real
        }

        // 4. Modificação topológica real (subdivisão refinada de triângulos na depressão)
        if (subdivide) {
            size_t tri_count = work_indices.size() / 3;
            for (size_t t = 0; t < tri_count; ++t) {
                uint32_t i0 = work_indices[t * 3 + 0];
                uint32_t i1 = work_indices[t * 3 + 1];
                uint32_t i2 = work_indices[t * 3 + 2];

                if (i0 >= work_verts.size() || i1 >= work_verts.size() || i2 >= work_verts.size()) {
                    continue;
                }

                const auto& v0 = work_verts[i0];
                const auto& v1 = work_verts[i1];
                const auto& v2 = work_verts[i2];

                // Centroide do triângulo
                float cx = (v0.position[0] + v1.position[0] + v2.position[0]) / 3.0f;
                float cy = (v0.position[1] + v1.position[1] + v2.position[1]) / 3.0f;
                float cz = (v0.position[2] + v1.position[2] + v2.position[2]) / 3.0f;

                float c_d = std::sqrt((cx - center[0])*(cx - center[0]) +
                                      (cy - center[1])*(cy - center[1]) +
                                      (cz - center[2])*(cz - center[2]));

                // Se o centroide estiver no núcleo da cratera e houver espaço no cluster (<=255 verts por índice uint8, <=128 tris)
                if (c_d < radius * 0.85f && work_verts.size() + 1 <= 255 && (work_indices.size() / 3) + 2 <= 128) {
                    Vertex v_new;
                    v_new.position[0] = cx;
                    v_new.position[1] = cy;
                    v_new.position[2] = cz;

                    float avg_nx = (v0.normal[0] + v1.normal[0] + v2.normal[0]) / 3.0f;
                    float avg_ny = (v0.normal[1] + v1.normal[1] + v2.normal[1]) / 3.0f;
                    float avg_nz = (v0.normal[2] + v1.normal[2] + v2.normal[2]) / 3.0f;
                    float n_len = std::sqrt(avg_nx * avg_nx + avg_ny * avg_ny + avg_nz * avg_nz);
                    if (n_len > 1e-6f) {
                        avg_nx /= n_len; avg_ny /= n_len; avg_nz /= n_len;
                    }
                    v_new.normal[0] = avg_nx;
                    v_new.normal[1] = avg_ny;
                    v_new.normal[2] = avg_nz;

                    v_new.uv[0] = (v0.uv[0] + v1.uv[0] + v2.uv[0]) / 3.0f;
                    v_new.uv[1] = (v0.uv[1] + v1.uv[1] + v2.uv[1]) / 3.0f;

                    // Desloca o novo vértice reforçando a profundidade local da depressão
                    float ct = c_d / radius;
                    float c_falloff = (1.0f - ct) * (1.0f - ct);
                    v_new.position[0] -= avg_nx * (depth * 0.35f * c_falloff);
                    v_new.position[1] -= avg_ny * (depth * 0.35f * c_falloff);
                    v_new.position[2] -= avg_nz * (depth * 0.35f * c_falloff);

                    uint32_t new_idx = static_cast<uint32_t>(work_verts.size());
                    work_verts.push_back(v_new);

                    // Divide o triângulo t em 3 subtriângulos:
                    // Triângulo original vira (i0, i1, new_idx)
                    work_indices[t * 3 + 0] = i0;
                    work_indices[t * 3 + 1] = i1;
                    work_indices[t * 3 + 2] = new_idx;

                    // Dois novos triângulos no final
                    work_indices.push_back(i1);
                    work_indices.push_back(i2);
                    work_indices.push_back(new_idx);

                    work_indices.push_back(i2);
                    work_indices.push_back(i0);
                    work_indices.push_back(new_idx);
                }
            }
        }

        // 5. Recalcula normais geométricas reais de faces e vértices
        for (auto& v : work_verts) {
            v.normal[0] = 0.0f;
            v.normal[1] = 0.0f;
            v.normal[2] = 0.0f;
        }

        size_t final_tri_count = work_indices.size() / 3;
        for (size_t t = 0; t < final_tri_count; ++t) {
            uint32_t i0 = work_indices[t * 3 + 0];
            uint32_t i1 = work_indices[t * 3 + 1];
            uint32_t i2 = work_indices[t * 3 + 2];

            const float* p0 = work_verts[i0].position;
            const float* p1 = work_verts[i1].position;
            const float* p2 = work_verts[i2].position;

            float e1x = p1[0] - p0[0], e1y = p1[1] - p0[1], e1z = p1[2] - p0[2];
            float e2x = p2[0] - p0[0], e2y = p2[1] - p0[1], e2z = p2[2] - p0[2];

            float fnx = e1y * e2z - e1z * e2y;
            float fny = e1z * e2x - e1x * e2z;
            float fnz = e1x * e2y - e1y * e2x;

            work_verts[i0].normal[0] += fnx; work_verts[i0].normal[1] += fny; work_verts[i0].normal[2] += fnz;
            work_verts[i1].normal[0] += fnx; work_verts[i1].normal[1] += fny; work_verts[i1].normal[2] += fnz;
            work_verts[i2].normal[0] += fnx; work_verts[i2].normal[1] += fny; work_verts[i2].normal[2] += fnz;
        }

        for (auto& v : work_verts) {
            float len = std::sqrt(v.normal[0] * v.normal[0] + v.normal[1] * v.normal[1] + v.normal[2] * v.normal[2]);
            if (len > 1e-6f) {
                v.normal[0] /= len;
                v.normal[1] /= len;
                v.normal[2] /= len;
            } else {
                v.normal[0] = 0.0f; v.normal[1] = 1.0f; v.normal[2] = 0.0f;
            }
        }

        // 6. Recalcula volumes delimitadores do cluster (AABB e Bounding Sphere)
        float bmin[3] = {  1e9f,  1e9f,  1e9f };
        float bmax[3] = { -1e9f, -1e9f, -1e9f };
        float avg_norm[3] = { 0.0f, 0.0f, 0.0f };

        for (const auto& v : work_verts) {
            bmin[0] = std::min(bmin[0], v.position[0]);
            bmin[1] = std::min(bmin[1], v.position[1]);
            bmin[2] = std::min(bmin[2], v.position[2]);

            bmax[0] = std::max(bmax[0], v.position[0]);
            bmax[1] = std::max(bmax[1], v.position[1]);
            bmax[2] = std::max(bmax[2], v.position[2]);

            avg_norm[0] += v.normal[0];
            avg_norm[1] += v.normal[1];
            avg_norm[2] += v.normal[2];
        }

        float cl_center[3] = {
            (bmin[0] + bmax[0]) * 0.5f,
            (bmin[1] + bmax[1]) * 0.5f,
            (bmin[2] + bmax[2]) * 0.5f
        };

        float cl_radius = 0.0f;
        for (const auto& v : work_verts) {
            float dx = v.position[0] - cl_center[0];
            float dy = v.position[1] - cl_center[1];
            float dz = v.position[2] - cl_center[2];
            cl_radius = std::max(cl_radius, std::sqrt(dx * dx + dy * dy + dz * dz));
        }

        float nlen = std::sqrt(avg_norm[0]*avg_norm[0] + avg_norm[1]*avg_norm[1] + avg_norm[2]*avg_norm[2]);
        if (nlen > 1e-6f) {
            avg_norm[0] /= nlen; avg_norm[1] /= nlen; avg_norm[2] /= nlen;
        } else {
            avg_norm[0] = 0.0f; avg_norm[1] = 1.0f; avg_norm[2] = 0.0f;
        }

        // 7. Constrói estruturas de substituição de cluster e GPU Cluster
        Cluster new_c{};
        new_c.id = c_idx;
        new_c.lod = 0;
        new_c.group = c.group;
        new_c.refined = c.refined;
        new_c.center[0] = cl_center[0];
        new_c.center[1] = cl_center[1];
        new_c.center[2] = cl_center[2];
        new_c.radius = cl_radius;
        new_c.cone[0] = avg_norm[0];
        new_c.cone[1] = avg_norm[1];
        new_c.cone[2] = avg_norm[2];
        new_c.cone[3] = c.cone[3]; // Preserva cutoff
        new_c.error = c.error;
        new_c.vertex_offset = 0;
        new_c.vertex_count = static_cast<uint32_t>(work_verts.size());
        new_c.triangle_offset = 0;
        new_c.triangle_count = static_cast<uint32_t>(work_indices.size() / 3);

        GPUCluster new_gc{};
        new_gc.center_radius[0] = cl_center[0];
        new_gc.center_radius[1] = cl_center[1];
        new_gc.center_radius[2] = cl_center[2];
        new_gc.center_radius[3] = cl_radius;

        new_gc.cone_axis_cutoff[0] = avg_norm[0];
        new_gc.cone_axis_cutoff[1] = avg_norm[1];
        new_gc.cone_axis_cutoff[2] = avg_norm[2];
        new_gc.cone_axis_cutoff[3] = c.cone[3];

        const auto& gpu_clusters = base_mesh.get_gpu_clusters();
        if (c_idx < gpu_clusters.size()) {
            std::memcpy(new_gc.group_bounds_error, gpu_clusters[c_idx].group_bounds_error, 4 * sizeof(float));
            std::memcpy(new_gc.refined_bounds_error, gpu_clusters[c_idx].refined_bounds_error, 4 * sizeof(float));
        }

        new_gc.data_offsets[0] = 0;
        new_gc.data_offsets[1] = new_c.vertex_count;
        new_gc.data_offsets[2] = 0;
        new_gc.data_offsets[3] = new_c.triangle_count;

        new_gc.cluster_info[0] = c_idx;
        new_gc.cluster_info[1] = 0;
        new_gc.cluster_info[2] = static_cast<uint32_t>(c.group);
        new_gc.cluster_info[3] = static_cast<uint32_t>(c.refined);

        // 8. Empacota vértices e triângulos para GPU SSBO
        std::vector<GPUPackedVertex> packed_v(work_verts.size());
        for (size_t v = 0; v < work_verts.size(); ++v) {
            packed_v[v].pos_x = work_verts[v].position[0];
            packed_v[v].pos_y = work_verts[v].position[1];
            packed_v[v].pos_z = work_verts[v].position[2];
            packed_v[v].uv_x  = work_verts[v].uv[0];
            packed_v[v].norm_x = work_verts[v].normal[0];
            packed_v[v].norm_y = work_verts[v].normal[1];
            packed_v[v].norm_z = work_verts[v].normal[2];
            packed_v[v].uv_y  = work_verts[v].uv[1];
        }

        size_t word_count = (work_indices.size() + 3) / 4;
        std::vector<uint32_t> packed_t(word_count, 0u);
        for (size_t idx = 0; idx < work_indices.size(); ++idx) {
            size_t w_idx = idx / 4;
            size_t b_idx = idx % 4;
            packed_t[w_idx] |= (static_cast<uint32_t>(work_indices[idx]) << (b_idx * 8));
        }

        // 9. Registra a região no overlay
        MutableRegion& reg = get_or_create_region(region_id);
        reg.region_id = region_id;
        reg.mesh_id = m_mesh_id;
        reg.instance_id = m_instance_id;
        reg.geometry_version = m_geometry_version;
        reg.parent_cluster_id = c_idx;
        reg.dirty_flags = MUTABLE_DIRTY_GEOMETRY | MUTABLE_DIRTY_BOUNDS | MUTABLE_DIRTY_DAG | MUTABLE_DIRTY_GPU_SYNC | MUTABLE_DIRTY_PHYSICS;

        reg.vertex_offset = 0;
        reg.vertex_count = static_cast<uint32_t>(work_verts.size());
        reg.index_offset = 0;
        reg.index_count = static_cast<uint32_t>(work_indices.size());
        reg.material_id = 0;
        reg.residency_state = MUTABLE_RESIDENCY_RESIDENT;

        reg.center[0] = cl_center[0];
        reg.center[1] = cl_center[1];
        reg.center[2] = cl_center[2];
        reg.radius = cl_radius;

        reg.aabb_min[0] = bmin[0];
        reg.aabb_min[1] = bmin[1];
        reg.aabb_min[2] = bmin[2];

        reg.aabb_max[0] = bmax[0];
        reg.aabb_max[1] = bmax[1];
        reg.aabb_max[2] = bmax[2];

        reg.vertices = std::move(work_verts);
        reg.indices = std::move(work_indices);
        reg.clusters = { new_c };
        reg.gpu_clusters = { new_gc };
        reg.packed_vertices = std::move(packed_v);
        reg.packed_triangles = std::move(packed_t);
        reg.replaced_cluster_ids = { c_idx };

        map_cluster_replacement(c_idx, region_id, 0);
        modified_count++;
    }

    if (modified_count > 0) {
        mark_dirty(MUTABLE_DIRTY_GEOMETRY | MUTABLE_DIRTY_BOUNDS | MUTABLE_DIRTY_DAG | MUTABLE_DIRTY_GPU_SYNC | MUTABLE_DIRTY_PHYSICS);
        bump_version();
    }

    return modified_count;
}

bool MutableGeometryOverlay::export_to_obj(const VGMeshResource& base_mesh, const std::string& filepath) const {
    if (!base_mesh.is_valid()) return false;

    try {
        std::filesystem::path p(filepath);
        if (p.has_parent_path()) {
            std::filesystem::create_directories(p.parent_path());
        }
    } catch (...) {}

    std::ofstream out(filepath);
    if (!out.is_open()) return false;

    out << "# ARBORIA ENGINE — VIRTUAL GEOMETRY MUTABLE OVERLAY EXPORT\n";
    out << "# Instancia: " << m_instance_id << " Versao Geometria: " << m_geometry_version << "\n";
    out << "# Clusters Modificados Substituidos: " << m_cluster_replacements.size() << "\n\n";

    const auto& lods = base_mesh.get_lods();
    const auto& clusters = base_mesh.get_clusters();
    const auto& base_vertices = base_mesh.get_vertices();
    const auto& base_indices = base_mesh.get_indices();

    uint32_t lod0_offset = 0;
    uint32_t lod0_count = static_cast<uint32_t>(clusters.size());
    if (!lods.empty()) {
        lod0_offset = lods[0].offset;
        lod0_count = lods[0].clusters;
    }

    uint32_t global_vert_offset = 1; // OBJ é 1-indexado

    for (uint32_t i = 0; i < lod0_count; ++i) {
        uint32_t c_idx = lod0_offset + i;
        const auto& c = clusters[c_idx];

        out << "# Cluster " << c_idx;
        if (is_cluster_replaced(c_idx)) {
            out << " [MUTABLE OVERLAY MODIFIED]\n";
            const MutableRegion* reg = get_region(m_cluster_replacements.at(c_idx).region_id);
            if (!reg) continue;

            for (const auto& v : reg->vertices) {
                out << "v " << std::fixed << std::setprecision(6) << v.position[0] << " " << v.position[1] << " " << v.position[2] << "\n";
                out << "vn " << v.normal[0] << " " << v.normal[1] << " " << v.normal[2] << "\n";
                out << "vt " << v.uv[0] << " " << v.uv[1] << "\n";
            }

            size_t tri_count = reg->indices.size() / 3;
            for (size_t t = 0; t < tri_count; ++t) {
                uint32_t idx0 = global_vert_offset + reg->indices[t * 3 + 0];
                uint32_t idx1 = global_vert_offset + reg->indices[t * 3 + 1];
                uint32_t idx2 = global_vert_offset + reg->indices[t * 3 + 2];
                out << "f " << idx0 << "/" << idx0 << "/" << idx0 << " "
                            << idx1 << "/" << idx1 << "/" << idx1 << " "
                            << idx2 << "/" << idx2 << "/" << idx2 << "\n";
            }
            global_vert_offset += static_cast<uint32_t>(reg->vertices.size());
        } else {
            out << " [SHARED BASE GEOMETRY]\n";
            for (uint32_t v = 0; v < c.vertex_count; ++v) {
                const auto& vert = base_vertices[c.vertex_offset + v];
                out << "v " << std::fixed << std::setprecision(6) << vert.position[0] << " " << vert.position[1] << " " << vert.position[2] << "\n";
                out << "vn " << vert.normal[0] << " " << vert.normal[1] << " " << vert.normal[2] << "\n";
                out << "vt " << vert.uv[0] << " " << vert.uv[1] << "\n";
            }

            for (uint32_t t = 0; t < c.triangle_count; ++t) {
                uint32_t idx0 = global_vert_offset + base_indices[c.triangle_offset + t * 3 + 0];
                uint32_t idx1 = global_vert_offset + base_indices[c.triangle_offset + t * 3 + 1];
                uint32_t idx2 = global_vert_offset + base_indices[c.triangle_offset + t * 3 + 2];
                out << "f " << idx0 << "/" << idx0 << "/" << idx0 << " "
                            << idx1 << "/" << idx1 << "/" << idx1 << " "
                            << idx2 << "/" << idx2 << "/" << idx2 << "\n";
            }
            global_vert_offset += c.vertex_count;
        }
    }

    return true;
}

void MutableGeometryOverlay::get_combined_lod0_stats(const VGMeshResource& base_mesh, size_t& out_vertices, size_t& out_triangles) const {
    out_vertices = 0;
    out_triangles = 0;
    if (!base_mesh.is_valid()) return;

    const auto& lods = base_mesh.get_lods();
    const auto& clusters = base_mesh.get_clusters();

    uint32_t lod0_offset = 0;
    uint32_t lod0_count = static_cast<uint32_t>(clusters.size());
    if (!lods.empty()) {
        lod0_offset = lods[0].offset;
        lod0_count = lods[0].clusters;
    }

    for (uint32_t i = 0; i < lod0_count; ++i) {
        uint32_t c_idx = lod0_offset + i;
        if (is_cluster_replaced(c_idx)) {
            const MutableRegion* reg = get_region(m_cluster_replacements.at(c_idx).region_id);
            if (reg) {
                out_vertices += reg->vertices.size();
                out_triangles += reg->indices.size() / 3;
            }
        } else {
            out_vertices += clusters[c_idx].vertex_count;
            out_triangles += clusters[c_idx].triangle_count;
        }
    }
}

DAGReconstructionStats MutableGeometryOverlay::rebuild_dag_incremental(const VGMeshResource& base_mesh) {
    DAGReconstructionStats stats{};
    auto start_time = std::chrono::high_resolution_clock::now();

    if (!base_mesh.is_valid() || m_cluster_replacements.empty()) {
        return stats;
    }

    const auto& base_clusters = base_mesh.get_clusters();
    const auto& base_groups = base_mesh.get_groups();

    // 1. Identificar os clusters atingidos no LOD 0 e seus grupos DAG pais
    std::unordered_set<uint32_t> affected_groups;
    for (const auto& pair : m_cluster_replacements) {
        uint32_t orig_c_id = pair.first;
        if (orig_c_id < base_clusters.size()) {
            stats.modified_lod0_clusters++;
            int32_t parent_grp = base_clusters[orig_c_id].group;
            if (parent_grp >= 0 && static_cast<uint32_t>(parent_grp) < base_groups.size()) {
                affected_groups.insert(static_cast<uint32_t>(parent_grp));
            }
        }
    }
    stats.affected_groups = static_cast<uint32_t>(affected_groups.size());

    // 2. Para cada grupo DAG atingido, propaga a reconstrução incremental
    for (uint32_t grp_id : affected_groups) {
        // Encontra todos os clusters da malha pertencentes a este grupo (irmãos)
        std::vector<uint32_t> sibling_cluster_ids;
        for (size_t i = 0; i < base_clusters.size(); ++i) {
            if (base_clusters[i].group == static_cast<int32_t>(grp_id)) {
                sibling_cluster_ids.push_back(static_cast<uint32_t>(i));
            }
        }

        // Encontra clusters pais do grupo (clusters que têm refined == grp_id)
        std::vector<uint32_t> parent_cluster_ids;
        for (size_t i = 0; i < base_clusters.size(); ++i) {
            if (base_clusters[i].refined == static_cast<int32_t>(grp_id)) {
                parent_cluster_ids.push_back(static_cast<uint32_t>(i));
            }
        }

        // Se o grupo não tiver pais no DAG, já é o nível mais simplificado
        if (parent_cluster_ids.empty()) continue;

        // 3. Atualiza limites e erros geométricos dos clusters pais
        float grp_min[3] = {  1e9f,  1e9f,  1e9f };
        float grp_max[3] = { -1e9f, -1e9f, -1e9f };
        float max_child_error = 0.0f;

        for (uint32_t sib_id : sibling_cluster_ids) {
            if (is_cluster_replaced(sib_id)) {
                const MutableRegion* reg = get_region(m_cluster_replacements.at(sib_id).region_id);
                if (reg) {
                    grp_min[0] = std::min(grp_min[0], reg->aabb_min[0]);
                    grp_min[1] = std::min(grp_min[1], reg->aabb_min[1]);
                    grp_min[2] = std::min(grp_min[2], reg->aabb_min[2]);
                    grp_max[0] = std::max(grp_max[0], reg->aabb_max[0]);
                    grp_max[1] = std::max(grp_max[1], reg->aabb_max[1]);
                    grp_max[2] = std::max(grp_max[2], reg->aabb_max[2]);
                    max_child_error = std::max(max_child_error, reg->clusters[0].error);
                }
            } else if (sib_id < base_clusters.size()) {
                const auto& bc = base_clusters[sib_id];
                grp_min[0] = std::min(grp_min[0], bc.center[0] - bc.radius);
                grp_min[1] = std::min(grp_min[1], bc.center[1] - bc.radius);
                grp_min[2] = std::min(grp_min[2], bc.center[2] - bc.radius);
                grp_max[0] = std::max(grp_max[0], bc.center[0] + bc.radius);
                grp_max[1] = std::max(grp_max[1], bc.center[1] + bc.radius);
                grp_max[2] = std::max(grp_max[2], bc.center[2] + bc.radius);
                max_child_error = std::max(max_child_error, bc.error);
            }
        }

        float grp_center[3] = {
            (grp_min[0] + grp_max[0]) * 0.5f,
            (grp_min[1] + grp_max[1]) * 0.5f,
            (grp_min[2] + grp_max[2]) * 0.5f
        };
        float dx = grp_max[0] - grp_center[0];
        float dy = grp_max[1] - grp_center[1];
        float dz = grp_max[2] - grp_center[2];
        float grp_radius = std::sqrt(dx*dx + dy*dy + dz*dz);

        // Erro geométrico do grupo pai = erro da base com ampliação proporcional
        float new_grp_error = std::max(base_groups[grp_id].error, max_child_error * 1.25f + 0.05f);

        // 4. Propaga para os clusters pais reconstruídos
        for (uint32_t p_cid : parent_cluster_ids) {
            const auto& base_parent_c = base_clusters[p_cid];
            uint32_t p_region_id = 5000 + p_cid;

            MutableRegion& p_reg = get_or_create_region(p_region_id);
            p_reg.region_id = p_region_id;
            p_reg.mesh_id = m_mesh_id;
            p_reg.instance_id = m_instance_id;
            p_reg.geometry_version = m_geometry_version;
            p_reg.parent_cluster_id = p_cid;
            p_reg.dirty_flags = MUTABLE_DIRTY_DAG | MUTABLE_DIRTY_BOUNDS | MUTABLE_DIRTY_GPU_SYNC;

            // Cluster pai atualizado
            Cluster p_c = base_parent_c;
            p_c.center[0] = grp_center[0];
            p_c.center[1] = grp_center[1];
            p_c.center[2] = grp_center[2];
            p_c.radius = grp_radius;
            p_c.error = new_grp_error;

            GPUCluster p_gc{};
            p_gc.center_radius[0] = grp_center[0];
            p_gc.center_radius[1] = grp_center[1];
            p_gc.center_radius[2] = grp_center[2];
            p_gc.center_radius[3] = grp_radius;

            p_gc.cone_axis_cutoff[0] = base_parent_c.cone[0];
            p_gc.cone_axis_cutoff[1] = base_parent_c.cone[1];
            p_gc.cone_axis_cutoff[2] = base_parent_c.cone[2];
            p_gc.cone_axis_cutoff[3] = base_parent_c.cone[3];

            p_gc.refined_bounds_error[0] = grp_center[0];
            p_gc.refined_bounds_error[1] = grp_center[1];
            p_gc.refined_bounds_error[2] = grp_center[2];
            p_gc.refined_bounds_error[3] = new_grp_error;

            // Mantém referências do grupo pai
            if (p_c.group >= 0 && static_cast<uint32_t>(p_c.group) < base_groups.size()) {
                const auto& parent_grp_meta = base_groups[p_c.group];
                p_gc.group_bounds_error[0] = parent_grp_meta.center[0];
                p_gc.group_bounds_error[1] = parent_grp_meta.center[1];
                p_gc.group_bounds_error[2] = parent_grp_meta.center[2];
                p_gc.group_bounds_error[3] = parent_grp_meta.error;
            } else {
                p_gc.group_bounds_error[3] = 999999.0f;
            }

            p_gc.data_offsets[0] = base_parent_c.vertex_offset;
            p_gc.data_offsets[1] = base_parent_c.vertex_count;
            p_gc.data_offsets[2] = base_parent_c.triangle_offset;
            p_gc.data_offsets[3] = base_parent_c.triangle_count;

            p_gc.cluster_info[0] = p_cid;
            p_gc.cluster_info[1] = base_parent_c.lod;
            p_gc.cluster_info[2] = static_cast<uint32_t>(base_parent_c.group);
            p_gc.cluster_info[3] = static_cast<uint32_t>(base_parent_c.refined);

            p_reg.clusters = { p_c };
            p_reg.gpu_clusters = { p_gc };
            p_reg.replaced_cluster_ids = { p_cid };
            map_cluster_replacement(p_cid, p_region_id, 0);

            stats.rebuilt_parent_clusters++;
        }
    }

    stats.preserved_clusters = static_cast<uint32_t>(base_clusters.size()) - stats.modified_lod0_clusters - stats.rebuilt_parent_clusters;

    clear_dirty(MUTABLE_DIRTY_DAG);
    auto end_time = std::chrono::high_resolution_clock::now();
    stats.dag_update_time_ms = std::chrono::duration<float, std::milli>(end_time - start_time).count();

    return stats;
}

GPUMutableGeometryPatch MutableGeometryOverlay::prepare_gpu_geometry_patch(
    uint32_t global_dynamic_vertex_base,
    uint32_t global_dynamic_triangle_base
) {
    GPUMutableGeometryPatch patch{};
    patch.instance_id = m_instance_id;
    patch.geometry_version = m_geometry_version;
    patch.dynamic_vertex_offset = global_dynamic_vertex_base;
    patch.dynamic_triangle_offset = global_dynamic_triangle_base;

    uint32_t curr_v_offset = global_dynamic_vertex_base;
    uint32_t curr_t_offset = global_dynamic_triangle_base;

    for (auto& pair : m_regions) {
        MutableRegion& reg = pair.second;
        if (reg.vertices.empty()) continue;

        uint32_t reg_v_base = curr_v_offset;
        uint32_t reg_t_base = curr_t_offset;

        // Anexa vértices empacotados ao patch
        patch.dynamic_vertices.insert(patch.dynamic_vertices.end(), reg.packed_vertices.begin(), reg.packed_vertices.end());
        curr_v_offset += static_cast<uint32_t>(reg.packed_vertices.size());

        // Anexa palavras de triângulos empacotados ao patch
        patch.dynamic_triangles.insert(patch.dynamic_triangles.end(), reg.packed_triangles.begin(), reg.packed_triangles.end());
        curr_t_offset += static_cast<uint32_t>(reg.packed_triangles.size() * 4); // bytes

        // Atualiza os data_offsets dos GPUClusters desta região para apontar para o novo espaço dinâmico válido
        for (auto& gc : reg.gpu_clusters) {
            gc.data_offsets[0] = reg_v_base;
            gc.data_offsets[2] = reg_t_base;
            patch.updated_gpu_clusters.push_back(gc);
            patch.modified_cluster_count++;
        }

        reg.residency_state = MUTABLE_RESIDENCY_RESIDENT;
    }

    patch.dynamic_vertex_count = static_cast<uint32_t>(patch.dynamic_vertices.size());
    patch.dynamic_triangle_count = static_cast<uint32_t>(patch.dynamic_triangles.size());

    clear_dirty(MUTABLE_DIRTY_GPU_SYNC);
    return patch;
}

MutablePhysicsMesh MutableGeometryOverlay::build_physics_collision_mesh(const VGMeshResource& base_mesh) {
    MutablePhysicsMesh phys_mesh;
    if (!base_mesh.is_valid()) {
        phys_mesh.is_synchronized = false;
        return phys_mesh;
    }

    const auto& lods = base_mesh.get_lods();
    const auto& clusters = base_mesh.get_clusters();
    const auto& base_vertices = base_mesh.get_vertices();
    const auto& base_indices = base_mesh.get_indices();

    uint32_t lod0_offset = 0;
    uint32_t lod0_count = static_cast<uint32_t>(clusters.size());
    if (!lods.empty()) {
        lod0_offset = lods[0].offset;
        lod0_count = lods[0].clusters;
    }

    phys_mesh.aabb_min[0] = 1e9f; phys_mesh.aabb_min[1] = 1e9f; phys_mesh.aabb_min[2] = 1e9f;
    phys_mesh.aabb_max[0] = -1e9f; phys_mesh.aabb_max[1] = -1e9f; phys_mesh.aabb_max[2] = -1e9f;

    uint32_t vert_start_idx = 0;

    for (uint32_t i = 0; i < lod0_count; ++i) {
        uint32_t c_idx = lod0_offset + i;
        const auto& c = clusters[c_idx];

        if (is_cluster_replaced(c_idx)) {
            const MutableRegion* reg = get_region(m_cluster_replacements.at(c_idx).region_id);
            if (reg) {
                for (const auto& v : reg->vertices) {
                    phys_mesh.positions.push_back(v.position[0]);
                    phys_mesh.positions.push_back(v.position[1]);
                    phys_mesh.positions.push_back(v.position[2]);

                    phys_mesh.aabb_min[0] = std::min(phys_mesh.aabb_min[0], v.position[0]);
                    phys_mesh.aabb_min[1] = std::min(phys_mesh.aabb_min[1], v.position[1]);
                    phys_mesh.aabb_min[2] = std::min(phys_mesh.aabb_min[2], v.position[2]);

                    phys_mesh.aabb_max[0] = std::max(phys_mesh.aabb_max[0], v.position[0]);
                    phys_mesh.aabb_max[1] = std::max(phys_mesh.aabb_max[1], v.position[1]);
                    phys_mesh.aabb_max[2] = std::max(phys_mesh.aabb_max[2], v.position[2]);
                }
                for (uint32_t idx : reg->indices) {
                    phys_mesh.indices.push_back(vert_start_idx + idx);
                }
                vert_start_idx += static_cast<uint32_t>(reg->vertices.size());
            }
        } else {
            for (uint32_t v = 0; v < c.vertex_count; ++v) {
                const auto& vert = base_vertices[c.vertex_offset + v];
                phys_mesh.positions.push_back(vert.position[0]);
                phys_mesh.positions.push_back(vert.position[1]);
                phys_mesh.positions.push_back(vert.position[2]);

                phys_mesh.aabb_min[0] = std::min(phys_mesh.aabb_min[0], vert.position[0]);
                phys_mesh.aabb_min[1] = std::min(phys_mesh.aabb_min[1], vert.position[1]);
                phys_mesh.aabb_min[2] = std::min(phys_mesh.aabb_min[2], vert.position[2]);

                phys_mesh.aabb_max[0] = std::max(phys_mesh.aabb_max[0], vert.position[0]);
                phys_mesh.aabb_max[1] = std::max(phys_mesh.aabb_max[1], vert.position[1]);
                phys_mesh.aabb_max[2] = std::max(phys_mesh.aabb_max[2], vert.position[2]);
            }
            for (uint32_t t = 0; t < c.triangle_count * 3; ++t) {
                phys_mesh.indices.push_back(vert_start_idx + base_indices[c.triangle_offset + t]);
            }
            vert_start_idx += c.vertex_count;
        }
    }

    phys_mesh.is_synchronized = true;
    m_physics_mesh = phys_mesh;
    clear_dirty(MUTABLE_DIRTY_PHYSICS);

    return phys_mesh;
}

bool MutableGeometryOverlay::save_to_file(const std::string& filepath) const {
    try {
        std::filesystem::path p(filepath);
        if (p.has_parent_path()) {
            std::filesystem::create_directories(p.parent_path());
        }
    } catch (...) {}

    std::ofstream out(filepath, std::ios::binary);
    if (!out.is_open()) return false;

    const char magic[8] = "ARMUT01";
    out.write(magic, 8);

    uint32_t version = 1;
    out.write(reinterpret_cast<const char*>(&version), sizeof(version));
    out.write(reinterpret_cast<const char*>(&m_instance_id), sizeof(m_instance_id));
    out.write(reinterpret_cast<const char*>(&m_mesh_id), sizeof(m_mesh_id));
    out.write(reinterpret_cast<const char*>(&m_geometry_version), sizeof(m_geometry_version));

    uint32_t region_count = static_cast<uint32_t>(m_regions.size());
    out.write(reinterpret_cast<const char*>(&region_count), sizeof(region_count));

    for (const auto& pair : m_regions) {
        const MutableRegion& reg = pair.second;
        out.write(reinterpret_cast<const char*>(&reg.region_id), sizeof(reg.region_id));
        out.write(reinterpret_cast<const char*>(&reg.mesh_id), sizeof(reg.mesh_id));
        out.write(reinterpret_cast<const char*>(&reg.instance_id), sizeof(reg.instance_id));
        out.write(reinterpret_cast<const char*>(&reg.geometry_version), sizeof(reg.geometry_version));
        out.write(reinterpret_cast<const char*>(&reg.parent_cluster_id), sizeof(reg.parent_cluster_id));
        out.write(reinterpret_cast<const char*>(&reg.dirty_flags), sizeof(reg.dirty_flags));

        out.write(reinterpret_cast<const char*>(&reg.vertex_offset), sizeof(reg.vertex_offset));
        out.write(reinterpret_cast<const char*>(&reg.vertex_count), sizeof(reg.vertex_count));
        out.write(reinterpret_cast<const char*>(&reg.index_offset), sizeof(reg.index_offset));
        out.write(reinterpret_cast<const char*>(&reg.index_count), sizeof(reg.index_count));
        out.write(reinterpret_cast<const char*>(&reg.material_id), sizeof(reg.material_id));
        out.write(reinterpret_cast<const char*>(&reg.residency_state), sizeof(reg.residency_state));

        out.write(reinterpret_cast<const char*>(reg.center), sizeof(reg.center));
        out.write(reinterpret_cast<const char*>(&reg.radius), sizeof(reg.radius));
        out.write(reinterpret_cast<const char*>(reg.aabb_min), sizeof(reg.aabb_min));
        out.write(reinterpret_cast<const char*>(reg.aabb_max), sizeof(reg.aabb_max));

        // Replaced cluster IDs
        uint32_t rep_count = static_cast<uint32_t>(reg.replaced_cluster_ids.size());
        out.write(reinterpret_cast<const char*>(&rep_count), sizeof(rep_count));
        if (rep_count > 0) {
            out.write(reinterpret_cast<const char*>(reg.replaced_cluster_ids.data()), rep_count * sizeof(uint32_t));
        }

        // Vertices
        uint32_t v_count = static_cast<uint32_t>(reg.vertices.size());
        out.write(reinterpret_cast<const char*>(&v_count), sizeof(v_count));
        if (v_count > 0) {
            out.write(reinterpret_cast<const char*>(reg.vertices.data()), v_count * sizeof(Vertex));
        }

        // Indices
        uint32_t i_count = static_cast<uint32_t>(reg.indices.size());
        out.write(reinterpret_cast<const char*>(&i_count), sizeof(i_count));
        if (i_count > 0) {
            out.write(reinterpret_cast<const char*>(reg.indices.data()), i_count * sizeof(uint32_t));
        }

        // Clusters
        uint32_t c_count = static_cast<uint32_t>(reg.clusters.size());
        out.write(reinterpret_cast<const char*>(&c_count), sizeof(c_count));
        if (c_count > 0) {
            out.write(reinterpret_cast<const char*>(reg.clusters.data()), c_count * sizeof(Cluster));
        }

        // GPUClusters
        uint32_t gc_count = static_cast<uint32_t>(reg.gpu_clusters.size());
        out.write(reinterpret_cast<const char*>(&gc_count), sizeof(gc_count));
        if (gc_count > 0) {
            out.write(reinterpret_cast<const char*>(reg.gpu_clusters.data()), gc_count * sizeof(GPUCluster));
        }

        // Packed Vertices
        uint32_t pv_count = static_cast<uint32_t>(reg.packed_vertices.size());
        out.write(reinterpret_cast<const char*>(&pv_count), sizeof(pv_count));
        if (pv_count > 0) {
            out.write(reinterpret_cast<const char*>(reg.packed_vertices.data()), pv_count * sizeof(GPUPackedVertex));
        }

        // Packed Triangles
        uint32_t pt_count = static_cast<uint32_t>(reg.packed_triangles.size());
        out.write(reinterpret_cast<const char*>(&pt_count), sizeof(pt_count));
        if (pt_count > 0) {
            out.write(reinterpret_cast<const char*>(reg.packed_triangles.data()), pt_count * sizeof(uint32_t));
        }
    }

    // Replacements map
    uint32_t map_count = static_cast<uint32_t>(m_cluster_replacements.size());
    out.write(reinterpret_cast<const char*>(&map_count), sizeof(map_count));
    for (const auto& pair : m_cluster_replacements) {
        uint32_t orig_c_id = pair.first;
        uint32_t r_id = pair.second.region_id;
        uint32_t l_idx = pair.second.local_cluster_idx;
        out.write(reinterpret_cast<const char*>(&orig_c_id), sizeof(orig_c_id));
        out.write(reinterpret_cast<const char*>(&r_id), sizeof(r_id));
        out.write(reinterpret_cast<const char*>(&l_idx), sizeof(l_idx));
    }

    return out.good();
}

bool MutableGeometryOverlay::load_from_file(const std::string& filepath, const VGMeshResource& base_mesh) {
    std::ifstream in(filepath, std::ios::binary);
    if (!in.is_open()) return false;

    char magic[8] = {0};
    in.read(magic, 8);
    if (std::memcmp(magic, "ARMUT01", 7) != 0) {
        return false;
    }

    uint32_t version = 0;
    in.read(reinterpret_cast<char*>(&version), sizeof(version));
    if (version != 1) {
        return false;
    }

    uint32_t inst_id = 0, m_id = 0, geom_version = 0, region_count = 0;
    in.read(reinterpret_cast<char*>(&inst_id), sizeof(inst_id));
    in.read(reinterpret_cast<char*>(&m_id), sizeof(m_id));
    in.read(reinterpret_cast<char*>(&geom_version), sizeof(geom_version));
    in.read(reinterpret_cast<char*>(&region_count), sizeof(region_count));

    clear();
    m_mesh_id = m_id;
    m_geometry_version = geom_version;

    for (uint32_t r = 0; r < region_count; ++r) {
        MutableRegion reg{};
        in.read(reinterpret_cast<char*>(&reg.region_id), sizeof(reg.region_id));
        in.read(reinterpret_cast<char*>(&reg.mesh_id), sizeof(reg.mesh_id));
        in.read(reinterpret_cast<char*>(&reg.instance_id), sizeof(reg.instance_id));
        in.read(reinterpret_cast<char*>(&reg.geometry_version), sizeof(reg.geometry_version));
        in.read(reinterpret_cast<char*>(&reg.parent_cluster_id), sizeof(reg.parent_cluster_id));
        in.read(reinterpret_cast<char*>(&reg.dirty_flags), sizeof(reg.dirty_flags));

        in.read(reinterpret_cast<char*>(&reg.vertex_offset), sizeof(reg.vertex_offset));
        in.read(reinterpret_cast<char*>(&reg.vertex_count), sizeof(reg.vertex_count));
        in.read(reinterpret_cast<char*>(&reg.index_offset), sizeof(reg.index_offset));
        in.read(reinterpret_cast<char*>(&reg.index_count), sizeof(reg.index_count));
        in.read(reinterpret_cast<char*>(&reg.material_id), sizeof(reg.material_id));
        in.read(reinterpret_cast<char*>(&reg.residency_state), sizeof(reg.residency_state));

        in.read(reinterpret_cast<char*>(reg.center), sizeof(reg.center));
        in.read(reinterpret_cast<char*>(&reg.radius), sizeof(reg.radius));
        in.read(reinterpret_cast<char*>(reg.aabb_min), sizeof(reg.aabb_min));
        in.read(reinterpret_cast<char*>(reg.aabb_max), sizeof(reg.aabb_max));

        // Replaced cluster IDs
        uint32_t rep_count = 0;
        in.read(reinterpret_cast<char*>(&rep_count), sizeof(rep_count));
        reg.replaced_cluster_ids.resize(rep_count);
        if (rep_count > 0) {
            in.read(reinterpret_cast<char*>(reg.replaced_cluster_ids.data()), rep_count * sizeof(uint32_t));
        }

        // Vertices
        uint32_t v_count = 0;
        in.read(reinterpret_cast<char*>(&v_count), sizeof(v_count));
        reg.vertices.resize(v_count);
        if (v_count > 0) {
            in.read(reinterpret_cast<char*>(reg.vertices.data()), v_count * sizeof(Vertex));
        }

        // Indices
        uint32_t i_count = 0;
        in.read(reinterpret_cast<char*>(&i_count), sizeof(i_count));
        reg.indices.resize(i_count);
        if (i_count > 0) {
            in.read(reinterpret_cast<char*>(reg.indices.data()), i_count * sizeof(uint32_t));
        }

        // Clusters
        uint32_t c_count = 0;
        in.read(reinterpret_cast<char*>(&c_count), sizeof(c_count));
        reg.clusters.resize(c_count);
        if (c_count > 0) {
            in.read(reinterpret_cast<char*>(reg.clusters.data()), c_count * sizeof(Cluster));
        }

        // GPUClusters
        uint32_t gc_count = 0;
        in.read(reinterpret_cast<char*>(&gc_count), sizeof(gc_count));
        reg.gpu_clusters.resize(gc_count);
        if (gc_count > 0) {
            in.read(reinterpret_cast<char*>(reg.gpu_clusters.data()), gc_count * sizeof(GPUCluster));
        }

        // Packed Vertices
        uint32_t pv_count = 0;
        in.read(reinterpret_cast<char*>(&pv_count), sizeof(pv_count));
        reg.packed_vertices.resize(pv_count);
        if (pv_count > 0) {
            in.read(reinterpret_cast<char*>(reg.packed_vertices.data()), pv_count * sizeof(GPUPackedVertex));
        }

        // Packed Triangles
        uint32_t pt_count = 0;
        in.read(reinterpret_cast<char*>(&pt_count), sizeof(pt_count));
        reg.packed_triangles.resize(pt_count);
        if (pt_count > 0) {
            in.read(reinterpret_cast<char*>(reg.packed_triangles.data()), pt_count * sizeof(uint32_t));
        }

        m_regions[reg.region_id] = std::move(reg);
    }

    // Replacements map
    uint32_t map_count = 0;
    in.read(reinterpret_cast<char*>(&map_count), sizeof(map_count));
    for (uint32_t m = 0; m < map_count; ++m) {
        uint32_t orig_c_id = 0, r_id = 0, l_idx = 0;
        in.read(reinterpret_cast<char*>(&orig_c_id), sizeof(orig_c_id));
        in.read(reinterpret_cast<char*>(&r_id), sizeof(r_id));
        in.read(reinterpret_cast<char*>(&l_idx), sizeof(l_idx));
        m_cluster_replacements[orig_c_id] = { r_id, l_idx };
    }

    mark_dirty(MUTABLE_DIRTY_GPU_SYNC | MUTABLE_DIRTY_PHYSICS | MUTABLE_DIRTY_BOUNDS);

    if (base_mesh.is_valid()) {
        build_physics_collision_mesh(base_mesh);
    }

    return in.good() || in.eof();
}

} // namespace Arboria

