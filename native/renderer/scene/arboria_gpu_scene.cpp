#include "arboria_gpu_scene.h"
#include <cmath>
#include <algorithm>
#include <cstring>

namespace Arboria {

ArboriaGPUScene& ArboriaGPUScene::instance() {
    static ArboriaGPUScene s_inst;
    return s_inst;
}

void ArboriaGPUScene::extract_frustum_planes(const float vp[16], float planes[6][4]) {
    // Linhas da matriz VP (col-major)
    // r0 = (vp[0], vp[4], vp[8],  vp[12])
    // r1 = (vp[1], vp[5], vp[9],  vp[13])
    // r2 = (vp[2], vp[6], vp[10], vp[14])
    // r3 = (vp[3], vp[7], vp[11], vp[15])
    float r0[4] = { vp[0], vp[4], vp[8],  vp[12] };
    float r1[4] = { vp[1], vp[5], vp[9],  vp[13] };
    float r2[4] = { vp[2], vp[6], vp[10], vp[14] };
    float r3[4] = { vp[3], vp[7], vp[11], vp[15] };

    float raw[6][4];
    // Left: r3 + r0
    for (int j = 0; j < 4; ++j) raw[0][j] = r3[j] + r0[j];
    // Right: r3 - r0
    for (int j = 0; j < 4; ++j) raw[1][j] = r3[j] - r0[j];
    // Bottom: r3 + r1
    for (int j = 0; j < 4; ++j) raw[2][j] = r3[j] + r1[j];
    // Top: r3 - r1
    for (int j = 0; j < 4; ++j) raw[3][j] = r3[j] - r1[j];
    // Near (Reversed-Z): r2
    for (int j = 0; j < 4; ++j) raw[4][j] = r2[j];
    // Far: r3 - r2
    for (int j = 0; j < 4; ++j) raw[5][j] = r3[j] - r2[j];

    for (int i = 0; i < 6; ++i) {
        float len = std::sqrt(raw[i][0]*raw[i][0] + raw[i][1]*raw[i][1] + raw[i][2]*raw[i][2]);
        if (len > 1e-6f) {
            float inv = 1.0f / len;
            planes[i][0] = raw[i][0] * inv;
            planes[i][1] = raw[i][1] * inv;
            planes[i][2] = raw[i][2] * inv;
            planes[i][3] = raw[i][3] * inv;
        } else {
            planes[i][0] = 0; planes[i][1] = 0; planes[i][2] = 1; planes[i][3] = 0;
        }
    }
}

bool ArboriaGPUScene::test_frustum(const float center[3], float radius, const float planes[6][4]) {
    for (int i = 0; i < 6; ++i) {
        float d = planes[i][0] * center[0] + planes[i][1] * center[1] + planes[i][2] * center[2] + planes[i][3];
        if (d < -radius) return false;
    }
    return true;
}

bool ArboriaGPUScene::test_cone(const float center[3], float radius, const float axis_cutoff[4], const float cam_pos[3]) {
    float cutoff = axis_cutoff[3];
    if (cutoff >= 1.0f) return true;

    float c_to_cam[3] = {
        center[0] - cam_pos[0],
        center[1] - cam_pos[1],
        center[2] - cam_pos[2]
    };
    float dist = std::sqrt(c_to_cam[0]*c_to_cam[0] + c_to_cam[1]*c_to_cam[1] + c_to_cam[2]*c_to_cam[2]);
    float dot = c_to_cam[0] * axis_cutoff[0] + c_to_cam[1] * axis_cutoff[1] + c_to_cam[2] * axis_cutoff[2];
    return dot < (cutoff * dist + radius);
}

float ArboriaGPUScene::project_screen_error(
    const float center[3], float radius, float mesh_error,
    const float cam_pos[3], float vp_h, float fov_factor
) {
    float dx = center[0] - cam_pos[0];
    float dy = center[1] - cam_pos[1];
    float dz = center[2] - cam_pos[2];
    float dist = std::sqrt(dx*dx + dy*dy + dz*dz);
    float d_eff = std::max(dist - radius, 0.05f);
    return (mesh_error * vp_h) / (2.0f * d_eff * fov_factor);
}

GlobalSceneUniforms ArboriaGPUScene::build_scene_uniforms(
    const float view_proj[16],
    const float cam_pos[3],
    float fov_factor,
    float vp_width,
    float vp_height,
    float max_screen_error,
    uint32_t lod_mode,
    bool enable_frustum,
    bool enable_cone,
    uint32_t shading_mode,
    bool enable_hiz
) {
    GlobalSceneUniforms u{};
    std::memcpy(u.view_proj, view_proj, 16 * sizeof(float));
    extract_frustum_planes(view_proj, u.frustum_planes);

    u.camera_pos_fov[0] = cam_pos[0];
    u.camera_pos_fov[1] = cam_pos[1];
    u.camera_pos_fov[2] = cam_pos[2];
    u.camera_pos_fov[3] = fov_factor;

    u.viewport_params[0] = vp_width;
    u.viewport_params[1] = vp_height;
    u.viewport_params[2] = max_screen_error;
    u.viewport_params[3] = static_cast<float>(lod_mode);

    u.total_instances = static_cast<uint32_t>(ArboriaInstanceRegistry::instance().get_instance_count());
    
    // Contagem acumulada de itens de trabalho (total de clusters de todas as instâncias ativas)
    uint32_t total_work = 0;
    std::vector<GPUInstanceData> instances;
    ArboriaInstanceRegistry::instance().build_gpu_instance_buffer(instances);
    for (const auto& inst : instances) {
        total_work += inst.cluster_count;
    }
    u.total_work_items = total_work;

    u.enable_frustum_culling = enable_frustum ? 1u : 0u;
    u.enable_cone_culling = enable_cone ? 1u : 0u;
    u.shading_mode = shading_mode;
    u.enable_hiz = enable_hiz ? 1u : 0u;
    u.max_visible_items = ArboriaVisibilityManager::instance().get_capacity();

    return u;
}

SceneCullResult ArboriaGPUScene::simulate_cull_scene(const GlobalSceneUniforms& u) const {
    SceneCullResult result{};
    std::vector<GPUInstanceData> instances;
    ArboriaInstanceRegistry::instance().build_gpu_instance_buffer(instances);

    result.total_instances = static_cast<uint32_t>(instances.size());
    result.total_work_items = u.total_work_items;
    result.visible_items.reserve(std::min(u.max_visible_items, 65536u));

    const float* cam = u.camera_pos_fov;
    float vp_h = std::max(u.viewport_params[1], 1.0f);
    float fov = std::max(u.camera_pos_fov[3], 0.1f);
    float max_err = std::max(u.viewport_params[2], 0.1f);

    for (size_t inst_idx = 0; inst_idx < instances.size(); ++inst_idx) {
        const auto& inst = instances[inst_idx];
        if ((inst.visibility_flags & 1u) == 0) continue; // Instância invisível

        // 1. Frustum Culling em nível de Instância (descarte antecipado)
        if (u.enable_frustum_culling) {
            float bs_center[3] = { inst.bounding_sphere[0], inst.bounding_sphere[1], inst.bounding_sphere[2] };
            float bs_radius = inst.bounding_sphere[3];
            if (!test_frustum(bs_center, bs_radius, u.frustum_planes)) {
                continue; // Instância fora do frustum, descarta todos os seus clusters
            }
        }

        result.visible_instances++;

        const RegisteredMeshInfo* mesh_info = ArboriaMeshRegistry::instance().get_mesh_info_by_index(inst.mesh_id);
        if (!mesh_info || !mesh_info->resource) continue;

        const auto& clusters = mesh_info->resource->get_gpu_clusters();

        // Recupera overlay de geometria mutável se a instância possuir modificações
        Handle inst_handle(inst.instance_id, 1);
        auto overlay = ArboriaInstanceRegistry::instance().get_mutable_overlay(inst_handle);

        for (size_t c_idx = 0; c_idx < clusters.size(); ++c_idx) {
            GPUCluster c = clusters[c_idx];
            if (overlay && overlay->is_cluster_replaced(static_cast<uint32_t>(c_idx))) {
                const GPUCluster* rep = overlay->get_replacement_gpu_cluster(static_cast<uint32_t>(c_idx));
                if (rep) {
                    c = *rep;
                }
            }

            // Posição do cluster no espaço de mundo
            float local_c[3] = { c.center_radius[0], c.center_radius[1], c.center_radius[2] };
            float world_c[3] = {
                inst.model_matrix[0]*local_c[0] + inst.model_matrix[4]*local_c[1] + inst.model_matrix[8] *local_c[2] + inst.model_matrix[12],
                inst.model_matrix[1]*local_c[0] + inst.model_matrix[5]*local_c[1] + inst.model_matrix[9] *local_c[2] + inst.model_matrix[13],
                inst.model_matrix[2]*local_c[0] + inst.model_matrix[6]*local_c[1] + inst.model_matrix[10]*local_c[2] + inst.model_matrix[14]
            };
            float sx = std::sqrt(inst.model_matrix[0]*inst.model_matrix[0] + inst.model_matrix[1]*inst.model_matrix[1] + inst.model_matrix[2]*inst.model_matrix[2]);
            float sy = std::sqrt(inst.model_matrix[4]*inst.model_matrix[4] + inst.model_matrix[5]*inst.model_matrix[5] + inst.model_matrix[6]*inst.model_matrix[6]);
            float sz = std::sqrt(inst.model_matrix[8]*inst.model_matrix[8] + inst.model_matrix[9]*inst.model_matrix[9] + inst.model_matrix[10]*inst.model_matrix[10]);
            float world_r = c.center_radius[3] * std::max({ sx, sy, sz });

            // Frustum Culling por Cluster
            if (u.enable_frustum_culling) {
                if (!test_frustum(world_c, world_r, u.frustum_planes)) {
                    continue;
                }
            }

            // Normal Cone Culling por Cluster
            if (u.enable_cone_culling) {
                float local_axis[4] = { c.cone_axis_cutoff[0], c.cone_axis_cutoff[1], c.cone_axis_cutoff[2], c.cone_axis_cutoff[3] };
                // Transforma eixo do cone com normal_matrix
                float world_axis[4];
                world_axis[0] = inst.normal_matrix[0]*local_axis[0] + inst.normal_matrix[4]*local_axis[1] + inst.normal_matrix[8] *local_axis[2];
                world_axis[1] = inst.normal_matrix[1]*local_axis[0] + inst.normal_matrix[5]*local_axis[1] + inst.normal_matrix[9] *local_axis[2];
                world_axis[2] = inst.normal_matrix[2]*local_axis[0] + inst.normal_matrix[6]*local_axis[1] + inst.normal_matrix[10]*local_axis[2];
                float ax_len = std::sqrt(world_axis[0]*world_axis[0] + world_axis[1]*world_axis[1] + world_axis[2]*world_axis[2]);
                if (ax_len > 1e-6f) {
                    world_axis[0] /= ax_len; world_axis[1] /= ax_len; world_axis[2] /= ax_len;
                }
                world_axis[3] = local_axis[3];

                if (!test_cone(world_c, world_r, world_axis, cam)) {
                    continue;
                }
            }

            // Seleção DAG
            bool selected = false;
            uint32_t lod_mode = static_cast<uint32_t>(inst.aabb_max[3]);
            if (lod_mode == 1) {
                // Modo Forçado
                uint32_t forced_lod = static_cast<uint32_t>(inst.material_metal_spec[3]);
                selected = (c.cluster_info[1] == forced_lod);
            } else {
                // Auto DAG
                bool parent_needed = false;
                float p_err = c.group_bounds_error[3];
                if (p_err > 10000.0f) {
                    parent_needed = true;
                } else {
                    float p_err_px = project_screen_error(world_c, 0.0f, p_err, cam, vp_h, fov);
                    parent_needed = (p_err_px > max_err);
                }

                bool child_satisfied = true;
                int refined_group = static_cast<int>(c.cluster_info[3]);
                if (refined_group >= 0) {
                    float r_err_px = project_screen_error(world_c, 0.0f, c.refined_bounds_error[3], cam, vp_h, fov);
                    child_satisfied = (r_err_px <= max_err);
                }

                selected = (parent_needed && child_satisfied);
            }

            if (selected) {
                if (result.visible_clusters < u.max_visible_items) {
                    VisibleClusterItem item;
                    item.instance_id = static_cast<uint32_t>(inst_idx);
                    item.cluster_id = inst.cluster_offset + static_cast<uint32_t>(c_idx);
                    result.visible_items.push_back(item);
                } else {
                    result.has_overflow = true;
                }
                result.visible_clusters++;
                result.total_triangles_drawn += c.data_offsets[3];
            }
        }
    }

    return result;
}

bool ArboriaGPUScene::dispatch_global_cull(
    const GPUDriverContext& ctx,
    const void* compute_pipeline,
    const void* global_uniform_set,
    uint32_t total_work_items
) {
    if (!ctx.call_method || !ctx.rd || !compute_pipeline || !global_uniform_set || total_work_items == 0) {
        return false;
    }

    // 1. Begin Compute List
    alignas(8) uint8_t cl_var[24] = {0};
    if (!ctx.call_method(ctx.rd, "compute_list_begin", nullptr, 0, cl_var)) {
        return false;
    }

    // 2. Bind Pipeline
    const void* bind_pipe_args[] = { cl_var, compute_pipeline };
    ctx.call_method(ctx.rd, "compute_list_bind_compute_pipeline", bind_pipe_args, 2, nullptr);

    // 3. Bind Global Uniform Set (Set 0)
    alignas(8) uint8_t set_idx_var[24] = {0};
    int64_t set_0 = 0;
    if (ctx.from_int) ctx.from_int(set_idx_var, &set_0);

    const void* bind_set_args[] = { cl_var, global_uniform_set, set_idx_var };
    ctx.call_method(ctx.rd, "compute_list_bind_uniform_set", bind_set_args, 3, nullptr);

    // 4. Dispatch único agrupado: ceil(total_work_items / 64)
    int64_t groups_x = (total_work_items + 63) / 64;
    alignas(8) uint8_t gx_var[24] = {0};
    if (ctx.from_int) ctx.from_int(gx_var, &groups_x);

    alignas(8) uint8_t one_var[24] = {0};
    int64_t one = 1;
    if (ctx.from_int) ctx.from_int(one_var, &one);

    const void* dispatch_args[] = { cl_var, gx_var, one_var, one_var };
    ctx.call_method(ctx.rd, "compute_list_dispatch", dispatch_args, 4, nullptr);

    // 5. End Compute List
    ctx.call_method(ctx.rd, "compute_list_end", nullptr, 0, nullptr);
    return true;
}

bool ArboriaGPUScene::draw_global_indirect(
    const GPUDriverContext& ctx,
    const void* framebuffer,
    const void* raster_pipeline,
    const void* raster_uniform_set,
    const void* indirect_args_buffer,
    const void* initial_colors
) {
    if (!ctx.call_method || !ctx.rd || !framebuffer || !raster_pipeline || !raster_uniform_set || !indirect_args_buffer) {
        return false;
    }

    // 1. Begin Draw List
    alignas(8) uint8_t clear_flags_var[24] = {0};
    int64_t clear_0 = 0;
    if (ctx.from_int) ctx.from_int(clear_flags_var, &clear_0);

    const void* colors_arg = initial_colors;
    const void* dl_begin_args[] = { framebuffer, clear_flags_var, colors_arg };
    alignas(8) uint8_t dl_var[24] = {0};
    if (!ctx.call_method(ctx.rd, "draw_list_begin", dl_begin_args, 3, dl_var)) {
        return false;
    }

    // 2. Bind Raster Pipeline
    const void* bind_pipe_args[] = { dl_var, raster_pipeline };
    ctx.call_method(ctx.rd, "draw_list_bind_render_pipeline", bind_pipe_args, 2, nullptr);

    // 3. Bind Global Raster Uniform Set (Set 0)
    alignas(8) uint8_t set_idx_var[24] = {0};
    int64_t set_0 = 0;
    if (ctx.from_int) ctx.from_int(set_idx_var, &set_0);

    const void* bind_set_args[] = { dl_var, raster_uniform_set, set_idx_var };
    ctx.call_method(ctx.rd, "draw_list_bind_uniform_set", bind_set_args, 3, nullptr);

    // 4. Executa 1 Desenho Indireto Agrupado Global (draw_count = 1)
    // Desenha todos os clusters visíveis de toda a cena em UMA única chamada Vulkan!
    alignas(8) uint8_t false_var[24] = {0};
    uint8_t val_false = 0;
    if (ctx.from_bool) ctx.from_bool(false_var, &val_false);

    alignas(8) uint8_t offset_var[24] = {0};
    int64_t offset_0 = 0;
    if (ctx.from_int) ctx.from_int(offset_var, &offset_0);

    alignas(8) uint8_t count_var[24] = {0};
    int64_t count_1 = 1;
    if (ctx.from_int) ctx.from_int(count_var, &count_1);

    alignas(8) uint8_t stride_var[24] = {0};
    int64_t stride_16 = 16;
    if (ctx.from_int) ctx.from_int(stride_var, &stride_16);

    const void* draw_args[] = { dl_var, false_var, indirect_args_buffer, offset_var, count_var, stride_var };
    ctx.call_method(ctx.rd, "draw_list_draw_indirect", draw_args, 6, nullptr);

    // 5. End Draw List
    ctx.call_method(ctx.rd, "draw_list_end", nullptr, 0, nullptr);
    return true;
}

} // namespace Arboria
