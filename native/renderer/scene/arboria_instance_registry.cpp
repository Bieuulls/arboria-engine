#include "arboria_instance_registry.h"
#include "arboria_mesh_registry.h"
#include "arboria_material_table.h"
#include <cmath>
#include <algorithm>
#include <cstring>
#include <iostream>

namespace Arboria {

ArboriaInstanceRegistry& ArboriaInstanceRegistry::instance() {
    static ArboriaInstanceRegistry s_inst;
    return s_inst;
}

Handle ArboriaInstanceRegistry::register_instance(Handle mesh_handle, uint32_t material_id) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (!ArboriaMeshRegistry::instance().is_valid_mesh(mesh_handle)) {
        std::cerr << "[ArboriaInstanceRegistry] Erro: Tentativa de instanciar malha invalida (Handle: " 
                  << mesh_handle.to_u64() << ")" << std::endl;
        return Handle{};
    }

    InstanceRecord rec;
    rec.mesh_handle = mesh_handle;
    rec.material_id = material_id;

    Handle h = m_instance_pool.allocate(rec);
    if (m_instance_pool.is_valid(h)) {
        m_instance_pool.get(h)->handle = h;
    }
    return h;
}

bool ArboriaInstanceRegistry::unregister_instance(Handle instance_handle) {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_instance_pool.release(instance_handle);
}

bool ArboriaInstanceRegistry::is_valid_instance(Handle instance_handle) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_instance_pool.is_valid(instance_handle);
}

bool ArboriaInstanceRegistry::set_transform(Handle instance_handle, const float transform_matrix[16]) {
    std::lock_guard<std::mutex> lock(m_mutex);
    InstanceRecord* rec = m_instance_pool.get(instance_handle);
    if (!rec) return false;
    std::memcpy(rec->model_matrix, transform_matrix, 16 * sizeof(float));
    return true;
}

bool ArboriaInstanceRegistry::set_lod_parameters(Handle instance_handle, float max_screen_error, uint32_t lod_mode, uint32_t forced_lod) {
    std::lock_guard<std::mutex> lock(m_mutex);
    InstanceRecord* rec = m_instance_pool.get(instance_handle);
    if (!rec) return false;
    rec->max_screen_error = max_screen_error;
    rec->lod_mode = lod_mode;
    rec->forced_lod = forced_lod;
    return true;
}

bool ArboriaInstanceRegistry::set_visibility(Handle instance_handle, bool visible) {
    std::lock_guard<std::mutex> lock(m_mutex);
    InstanceRecord* rec = m_instance_pool.get(instance_handle);
    if (!rec) return false;
    rec->visible = visible;
    return true;
}

bool ArboriaInstanceRegistry::set_material(Handle instance_handle, uint32_t material_id) {
    std::lock_guard<std::mutex> lock(m_mutex);
    InstanceRecord* rec = m_instance_pool.get(instance_handle);
    if (!rec) return false;
    rec->material_id = material_id;
    return true;
}

const InstanceRecord* ArboriaInstanceRegistry::get_instance(Handle instance_handle) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_instance_pool.get(instance_handle);
}

size_t ArboriaInstanceRegistry::get_instance_count() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_instance_pool.active_count();
}

void ArboriaInstanceRegistry::clear() {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_instance_pool.clear();
}

// Inversa transposta da matriz 3x3 de transformação normal (preserva vetores normais sob escala não uniforme)
void ArboriaInstanceRegistry::compute_normal_matrix(const float m[16], float normal_out[16]) {
    std::memset(normal_out, 0, 16 * sizeof(float));

    // Submatriz 3x3
    float a00 = m[0], a01 = m[1], a02 = m[2];
    float a10 = m[4], a11 = m[5], a12 = m[6];
    float a20 = m[8], a21 = m[9], a22 = m[10];

    float c00 = a11 * a22 - a12 * a21;
    float c01 = -(a10 * a22 - a12 * a20);
    float c02 = a10 * a21 - a11 * a20;

    float det = a00 * c00 + a01 * c01 + a02 * c02;
    if (std::abs(det) < 1e-6f) {
        normal_out[0] = 1.0f; normal_out[5] = 1.0f; normal_out[10] = 1.0f; normal_out[15] = 1.0f;
        return;
    }

    float inv_det = 1.0f / det;

    float c10 = -(a01 * a22 - a02 * a21);
    float c11 = a00 * a22 - a02 * a20;
    float c12 = -(a00 * a21 - a01 * a20);

    float c20 = a01 * a12 - a02 * a11;
    float c21 = -(a00 * a12 - a02 * a10);
    float c22 = a00 * a11 - a01 * a10;

    // Transposta da inversa
    normal_out[0] = c00 * inv_det;
    normal_out[1] = c10 * inv_det;
    normal_out[2] = c20 * inv_det;

    normal_out[4] = c01 * inv_det;
    normal_out[5] = c11 * inv_det;
    normal_out[6] = c21 * inv_det;

    normal_out[8] = c02 * inv_det;
    normal_out[9] = c12 * inv_det;
    normal_out[10] = c22 * inv_det;

    normal_out[15] = 1.0f;
}

// Bounding volumes considerando escala não-uniforme e reflexão (escalas negativas)
void ArboriaInstanceRegistry::compute_world_bounds(
    const float local_center[3], float local_radius,
    const float local_min[3], const float local_max[3],
    const float m[16],
    float out_world_center[3], float& out_world_radius,
    float out_world_min[3], float out_world_max[3]
) {
    // 1. Centro do bounding sphere no espaço de mundo
    out_world_center[0] = m[0] * local_center[0] + m[4] * local_center[1] + m[8]  * local_center[2] + m[12];
    out_world_center[1] = m[1] * local_center[0] + m[5] * local_center[1] + m[9]  * local_center[2] + m[13];
    out_world_center[2] = m[2] * local_center[0] + m[6] * local_center[1] + m[10] * local_center[2] + m[14];

    // Escala máxima dos três eixos da base
    float sx = std::sqrt(m[0]*m[0] + m[1]*m[1] + m[2]*m[2]);
    float sy = std::sqrt(m[4]*m[4] + m[5]*m[5] + m[6]*m[6]);
    float sz = std::sqrt(m[8]*m[8] + m[9]*m[9] + m[10]*m[10]);
    float max_scale = std::max({ sx, sy, sz });
    out_world_radius = local_radius * max_scale;

    // 2. AABB no espaço de mundo via Método de Jim Arvo (Graphics Gems I) - O(1) puro sem branches
    float c_loc[3] = {
        0.5f * (local_min[0] + local_max[0]),
        0.5f * (local_min[1] + local_max[1]),
        0.5f * (local_min[2] + local_max[2])
    };
    float e_loc[3] = {
        0.5f * (local_max[0] - local_min[0]),
        0.5f * (local_max[1] - local_min[1]),
        0.5f * (local_max[2] - local_min[2])
    };

    float c_world[3] = {
        m[0] * c_loc[0] + m[4] * c_loc[1] + m[8]  * c_loc[2] + m[12],
        m[1] * c_loc[0] + m[5] * c_loc[1] + m[9]  * c_loc[2] + m[13],
        m[2] * c_loc[0] + m[6] * c_loc[1] + m[10] * c_loc[2] + m[14]
    };

    float e_world[3] = {
        std::abs(m[0]) * e_loc[0] + std::abs(m[4]) * e_loc[1] + std::abs(m[8])  * e_loc[2],
        std::abs(m[1]) * e_loc[0] + std::abs(m[5]) * e_loc[1] + std::abs(m[9])  * e_loc[2],
        std::abs(m[2]) * e_loc[0] + std::abs(m[6]) * e_loc[1] + std::abs(m[10]) * e_loc[2]
    };

    out_world_min[0] = c_world[0] - e_world[0];
    out_world_min[1] = c_world[1] - e_world[1];
    out_world_min[2] = c_world[2] - e_world[2];

    out_world_max[0] = c_world[0] + e_world[0];
    out_world_max[1] = c_world[1] + e_world[1];
    out_world_max[2] = c_world[2] + e_world[2];
}

size_t ArboriaInstanceRegistry::build_gpu_instance_buffer(std::vector<GPUInstanceData>& out_buffer) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    out_buffer.clear();
    out_buffer.reserve(m_instance_pool.active_count());

    const auto& slots = m_instance_pool.get_slots();
    for (size_t i = 0; i < slots.size(); ++i) {
        if (!slots[i].active) continue;

        const InstanceRecord& rec = slots[i].data;
        const RegisteredMeshInfo* mesh_info = ArboriaMeshRegistry::instance().get_mesh_info(rec.mesh_handle);
        if (!mesh_info || !mesh_info->resource) continue;

        const Header& hdr = mesh_info->resource->get_header();

        GPUInstanceData gpu{};
        std::memcpy(gpu.model_matrix, rec.model_matrix, 16 * sizeof(float));
        compute_normal_matrix(rec.model_matrix, gpu.normal_matrix);

        // Bounds em espaço de mundo
        float bs_center[3] = {
            (hdr.bmin[0] + hdr.bmax[0]) * 0.5f,
            (hdr.bmin[1] + hdr.bmax[1]) * 0.5f,
            (hdr.bmin[2] + hdr.bmax[2]) * 0.5f
        };
        float dx = hdr.bmax[0] - bs_center[0];
        float dy = hdr.bmax[1] - bs_center[1];
        float dz = hdr.bmax[2] - bs_center[2];
        float bs_radius = std::sqrt(dx*dx + dy*dy + dz*dz);

        float w_center[3], w_radius, w_min[3], w_max[3];
        compute_world_bounds(
            bs_center, bs_radius,
            hdr.bmin, hdr.bmax,
            rec.model_matrix,
            w_center, w_radius, w_min, w_max
        );

        gpu.bounding_sphere[0] = w_center[0];
        gpu.bounding_sphere[1] = w_center[1];
        gpu.bounding_sphere[2] = w_center[2];
        gpu.bounding_sphere[3] = w_radius;

        gpu.aabb_min[0] = w_min[0];
        gpu.aabb_min[1] = w_min[1];
        gpu.aabb_min[2] = w_min[2];
        gpu.aabb_min[3] = rec.max_screen_error;

        gpu.aabb_max[0] = w_max[0];
        gpu.aabb_max[1] = w_max[1];
        gpu.aabb_max[2] = w_max[2];
        gpu.aabb_max[3] = static_cast<float>(rec.lod_mode);

        // Material PBR
        const MaterialRecord* mat = ArboriaMaterialTable::instance().get_material(rec.material_id);
        if (mat) {
            gpu.material_albedo_rough[0] = mat->albedo[0];
            gpu.material_albedo_rough[1] = mat->albedo[1];
            gpu.material_albedo_rough[2] = mat->albedo[2];
            gpu.material_albedo_rough[3] = mat->roughness;

            gpu.material_metal_spec[0] = mat->metallic;
            gpu.material_metal_spec[1] = mat->specular;
            gpu.material_metal_spec[2] = static_cast<float>(rec.material_id);
            gpu.material_metal_spec[3] = static_cast<float>(rec.forced_lod);
        } else {
            gpu.material_albedo_rough[0] = 0.8f;
            gpu.material_albedo_rough[1] = 0.82f;
            gpu.material_albedo_rough[2] = 0.85f;
            gpu.material_albedo_rough[3] = 0.5f;

            gpu.material_metal_spec[0] = 0.0f;
            gpu.material_metal_spec[1] = 0.5f;
            gpu.material_metal_spec[2] = 0.0f;
            gpu.material_metal_spec[3] = static_cast<float>(rec.forced_lod);
        }

        gpu.instance_id = static_cast<uint32_t>(out_buffer.size()); // Índice linear no SSBO
        gpu.mesh_id = rec.mesh_handle.index;

        float det = rec.model_matrix[0] * (rec.model_matrix[5] * rec.model_matrix[10] - rec.model_matrix[6] * rec.model_matrix[9])
                  - rec.model_matrix[1] * (rec.model_matrix[4] * rec.model_matrix[10] - rec.model_matrix[6] * rec.model_matrix[8])
                  + rec.model_matrix[2] * (rec.model_matrix[4] * rec.model_matrix[9]  - rec.model_matrix[5] * rec.model_matrix[8]);
        bool is_mirrored = (det < 0.0f);

        gpu.visibility_flags = (rec.visible ? 1u : 0u) | (rec.shadow_caster ? 2u : 0u) | (is_mirrored ? 4u : 0u);
        gpu.resource_generation = rec.handle.generation;
        gpu.cluster_offset = mesh_info->cluster_offset;
        gpu.cluster_count = mesh_info->cluster_count;

        out_buffer.push_back(gpu);
    }

    return out_buffer.size();
}

} // namespace Arboria
