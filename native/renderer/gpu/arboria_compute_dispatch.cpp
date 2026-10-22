#include "arboria_compute_dispatch.h"
#include <cmath>
#include <cstring>
#include <algorithm>

namespace Arboria {

VGComputeDispatch::VGComputeDispatch() {}
VGComputeDispatch::~VGComputeDispatch() {}

void VGComputeDispatch::extract_frustum_planes(const float m[16], float planes_out[6][4]) {
    // m is column-major 4x4 matrix
    // Row 0: m[0], m[4], m[8],  m[12]
    // Row 1: m[1], m[5], m[9],  m[13]
    // Row 2: m[2], m[6], m[10], m[14]
    // Row 3: m[3], m[7], m[11], m[15]

    float raw_planes[6][4] = {
        // Left: Row 3 + Row 0
        { m[3] + m[0], m[7] + m[4], m[11] + m[8], m[15] + m[12] },
        // Right: Row 3 - Row 0
        { m[3] - m[0], m[7] - m[4], m[11] - m[8], m[15] - m[12] },
        // Bottom: Row 3 + Row 1
        { m[3] + m[1], m[7] + m[5], m[11] + m[9], m[15] + m[13] },
        // Top: Row 3 - Row 1
        { m[3] - m[1], m[7] - m[5], m[11] - m[9], m[15] - m[13] },
        // Near: Row 2 (Godot Vulkan Reversed-Z clip)
        { m[2], m[6], m[10], m[14] },
        // Far: Row 3 - Row 2
        { m[3] - m[2], m[7] - m[6], m[11] - m[10], m[15] - m[14] }
    };

    for (int i = 0; i < 6; ++i) {
        float nx = raw_planes[i][0];
        float ny = raw_planes[i][1];
        float nz = raw_planes[i][2];
        float len = std::sqrt(nx * nx + ny * ny + nz * nz);
        if (len > 1e-6f) {
            planes_out[i][0] = nx / len;
            planes_out[i][1] = ny / len;
            planes_out[i][2] = nz / len;
            planes_out[i][3] = raw_planes[i][3] / len;
        } else {
            planes_out[i][0] = 0.0f;
            planes_out[i][1] = 1.0f;
            planes_out[i][2] = 0.0f;
            planes_out[i][3] = 0.0f;
        }
    }
}

CameraUniforms VGComputeDispatch::build_camera_uniforms(
    const CameraViewSettings& settings,
    uint32_t total_clusters,
    const float model_matrix[16]
) {
    CameraUniforms ubo{};

    // MVP Matrix
    if (model_matrix) {
        // Multiply view_proj * model_matrix (col-major 4x4)
        for (int col = 0; col < 4; ++col) {
            for (int row = 0; row < 4; ++row) {
                float sum = 0.0f;
                for (int k = 0; k < 4; ++k) {
                    sum += settings.view_proj_matrix[k * 4 + row] * model_matrix[col * 4 + k];
                }
                ubo.view_proj[col * 4 + row] = sum;
            }
        }
    } else {
        std::memcpy(ubo.view_proj, settings.view_proj_matrix, sizeof(ubo.view_proj));
    }

    // Frustum planes
    extract_frustum_planes(ubo.view_proj, ubo.frustum_planes);

    // camera_pos_fov: xyz = pos, w = fov_factor
    ubo.camera_pos_fov[0] = settings.camera_world_pos[0];
    ubo.camera_pos_fov[1] = settings.camera_world_pos[1];
    ubo.camera_pos_fov[2] = settings.camera_world_pos[2];
    ubo.camera_pos_fov[3] = 1.0f / std::tan(settings.fov_radians * 0.5f);

    // viewport_params: x = width, y = height, z = max_screen_error, w = lod_mode
    ubo.viewport_params[0] = settings.viewport_width;
    ubo.viewport_params[1] = settings.viewport_height;
    ubo.viewport_params[2] = settings.max_screen_error;
    ubo.viewport_params[3] = static_cast<float>(settings.lod_mode);

    // count_params: x = total_clusters, y = forced_lod, z = enable_frustum, w = enable_cone
    ubo.count_params[0] = total_clusters;
    ubo.count_params[1] = settings.forced_lod;
    ubo.count_params[2] = settings.enable_frustum_culling ? 1u : 0u;
    ubo.count_params[3] = settings.enable_cone_culling ? 1u : 0u;

    // render_params: x = shading_mode, y, z, w = 0
    ubo.render_params[0] = settings.shading_mode;
    ubo.render_params[1] = 0;
    ubo.render_params[2] = 0;
    ubo.render_params[3] = 0;

    return ubo;
}

uint32_t VGComputeDispatch::calculate_group_count(uint32_t total_clusters, uint32_t group_size) {
    if (group_size == 0) group_size = 64;
    // Quotient/remainder avoids uint32 overflow near UINT32_MAX.
    return total_clusters / group_size + (total_clusters % group_size != 0u ? 1u : 0u);
}

bool VGComputeDispatch::test_frustum(const float center[3], float radius, const float planes[6][4]) {
    for (int i = 0; i < 6; ++i) {
        float dot_prod = planes[i][0] * center[0] +
                         planes[i][1] * center[1] +
                         planes[i][2] * center[2];
        if (dot_prod + planes[i][3] < -radius) {
            return false;
        }
    }
    return true;
}

bool VGComputeDispatch::test_backface(const float center[3], float radius, const float cone[4], const float cam_pos[3]) {
    float cutoff = cone[3];
    if (cutoff >= 1.0f) return true; // Cones com cutoff >= 1 nao podem ser descartados

    float c_to_cam[3] = {
        center[0] - cam_pos[0],
        center[1] - cam_pos[1],
        center[2] - cam_pos[2]
    };
    float dist = std::sqrt(c_to_cam[0] * c_to_cam[0] +
                           c_to_cam[1] * c_to_cam[1] +
                           c_to_cam[2] * c_to_cam[2]);

    float dot_val = c_to_cam[0] * cone[0] +
                    c_to_cam[1] * cone[1] +
                    c_to_cam[2] * cone[2];

    return dot_val < (cutoff * dist + radius);
}

float VGComputeDispatch::project_error_to_screen(float error, float dist, float fov_factor, float viewport_height) {
    if (dist < 1e-4f) dist = 1e-4f;
    return (error / dist) * fov_factor * (viewport_height * 0.5f);
}

ComputeDispatchResult VGComputeDispatch::simulate_cull_offline(
    const VGMeshResource& mesh,
    const CameraUniforms& ubo
) {
    ComputeDispatchResult res{};
    if (!mesh.is_valid()) return res;

    const auto& clusters = mesh.get_clusters();
    const auto& gpu_clusters = mesh.get_gpu_clusters();
    uint32_t total = std::min(static_cast<uint32_t>(clusters.size()), ubo.count_params[0]);

    float cam_pos[3] = { ubo.camera_pos_fov[0], ubo.camera_pos_fov[1], ubo.camera_pos_fov[2] };
    float fov_factor = ubo.camera_pos_fov[3];
    float vp_h = ubo.viewport_params[1];
    float max_error = ubo.viewport_params[2];
    uint32_t lod_mode = static_cast<uint32_t>(ubo.viewport_params[3]);
    uint32_t forced_lod = ubo.count_params[1];
    bool use_frustum = (ubo.count_params[2] != 0u);
    bool use_cone = (ubo.count_params[3] != 0u);

    for (uint32_t i = 0; i < total; ++i) {
        res.clusters_evaluated++;
        const auto& c = clusters[i];
        const auto& gc = gpu_clusters[i];

        // 1. Frustum Culling
        if (use_frustum) {
            if (!test_frustum(c.center, c.radius, ubo.frustum_planes)) {
                continue;
            }
        }

        // 2. Normal Cone Culling
        if (use_cone) {
            if (!test_backface(c.center, c.radius, c.cone, cam_pos)) {
                continue;
            }
        }

        // 3. LOD Selection
        bool is_selected = false;
        if (lod_mode == 1u) {
            // Forced LOD
            if (c.lod == forced_lod) {
                is_selected = true;
            }
        } else {
            // Auto DAG LOD
            float p_center[3] = { gc.group_bounds_error[0], gc.group_bounds_error[1], gc.group_bounds_error[2] };
            float p_err = gc.group_bounds_error[3];
            float p_dist = std::sqrt(
                (p_center[0] - cam_pos[0]) * (p_center[0] - cam_pos[0]) +
                (p_center[1] - cam_pos[1]) * (p_center[1] - cam_pos[1]) +
                (p_center[2] - cam_pos[2]) * (p_center[2] - cam_pos[2])
            );
            float parent_screen_error = (p_err >= 999990.0f) ? 999999.0f : project_error_to_screen(p_err, p_dist, fov_factor, vp_h);

            float r_err = gc.refined_bounds_error[3];
            float refined_screen_error = -1.0f;
            if (r_err >= 0.0f) {
                float r_center[3] = { gc.refined_bounds_error[0], gc.refined_bounds_error[1], gc.refined_bounds_error[2] };
                float r_dist = std::sqrt(
                    (r_center[0] - cam_pos[0]) * (r_center[0] - cam_pos[0]) +
                    (r_center[1] - cam_pos[1]) * (r_center[1] - cam_pos[1]) +
                    (r_center[2] - cam_pos[2]) * (r_center[2] - cam_pos[2])
                );
                refined_screen_error = project_error_to_screen(r_err, r_dist, fov_factor, vp_h);
            }

            // Nanite DAG selection rule: parent_error > threshold && refined_error <= threshold
            if (parent_screen_error > max_error && refined_screen_error <= max_error) {
                is_selected = true;
            }
        }

        if (is_selected) {
            res.visible_cluster_ids.push_back(i);
            res.visible_cluster_count++;
            res.total_triangles_drawn += c.triangle_count;
        }
    }

    return res;
}

bool VGComputeDispatch::dispatch_cull_clusters_native(
    const GPUDriverContext& ctx,
    const void* compute_pipeline,
    const void* uniform_set,
    int64_t groups_x
) {
    if (!ctx.call_method || !ctx.rd || !compute_pipeline || !uniform_set || groups_x <= 0) return false;

    uint8_t cl_var[32] = {0};
    if (!ctx.call_method(ctx.rd, "compute_list_begin", nullptr, 0, cl_var)) {
        return false;
    }

    const void* bind_pipe_args[] = { cl_var, compute_pipeline };
    ctx.call_method(ctx.rd, "compute_list_bind_compute_pipeline", bind_pipe_args, 2, nullptr);

    uint8_t set_idx_var[32] = {0};
    int64_t set_0 = 0;
    if (ctx.from_int) ctx.from_int(set_idx_var, &set_0);

    const void* bind_set_args[] = { cl_var, uniform_set, set_idx_var };
    ctx.call_method(ctx.rd, "compute_list_bind_uniform_set", bind_set_args, 3, nullptr);

    uint8_t gx_var[32] = {0};
    if (ctx.from_int) ctx.from_int(gx_var, &groups_x);

    uint8_t one_var[32] = {0};
    int64_t one = 1;
    if (ctx.from_int) ctx.from_int(one_var, &one);

    const void* dispatch_args[] = { cl_var, gx_var, one_var, one_var };
    ctx.call_method(ctx.rd, "compute_list_dispatch", dispatch_args, 4, nullptr);

    ctx.call_method(ctx.rd, "compute_list_end", nullptr, 0, nullptr);
    return true;
}

bool VGComputeDispatch::dispatch_cull_clusters_batch(
    const GPUDriverContext& ctx,
    const void* compute_pipeline,
    const void* compute_sets_array,
    const void* groups_x_array,
    int64_t count
) {
    if (!ctx.call_method || !ctx.rd || !compute_pipeline || count <= 0) return false;

    uint8_t cl_var[32] = {0};
    if (!ctx.call_method(ctx.rd, "compute_list_begin", nullptr, 0, cl_var)) {
        return false;
    }

    const void* bind_pipe_args[] = { cl_var, compute_pipeline };
    ctx.call_method(ctx.rd, "compute_list_bind_compute_pipeline", bind_pipe_args, 2, nullptr);

    uint8_t set_idx_var[32] = {0};
    int64_t set_0 = 0;
    if (ctx.from_int) ctx.from_int(set_idx_var, &set_0);

    uint8_t one_var[32] = {0};
    int64_t one = 1;
    if (ctx.from_int) ctx.from_int(one_var, &one);

    for (int64_t i = 0; i < count; ++i) {
        uint8_t cset_var[32] = {0};
        uint8_t gx_var[32] = {0};
        uint8_t valid = 0, oob = 0;

        if (ctx.get_indexed) {
            ctx.get_indexed(compute_sets_array, i, cset_var, &valid, &oob);
            ctx.get_indexed(groups_x_array, i, gx_var, &valid, &oob);
        }

        const void* bind_set_args[] = { cl_var, cset_var, set_idx_var };
        ctx.call_method(ctx.rd, "compute_list_bind_uniform_set", bind_set_args, 3, nullptr);

        const void* dispatch_args[] = { cl_var, gx_var, one_var, one_var };
        ctx.call_method(ctx.rd, "compute_list_dispatch", dispatch_args, 4, nullptr);
    }

    ctx.call_method(ctx.rd, "compute_list_end", nullptr, 0, nullptr);
    return true;
}

} // namespace Arboria
