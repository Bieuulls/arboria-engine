#[compute]
#version 450

// ============================================================================
// ARBORIA VIRTUAL GEOMETRY — GPU SCENE GLOBAL CLUSTER CULLING & DAG LOD
// Arquitetura Global Batelada (1 Dispatch para Toda a Cena)
// Layout Binário Estrito std430 compatível com arboria_gpu_scene_types.h
// ============================================================================

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

struct GPUCluster {
    vec4 center_radius;        // xyz = center local, w = radius local
    vec4 cone_axis_cutoff;     // xyz = normal cone axis local, w = cutoff
    vec4 group_bounds_error;   // xyz = parent group center local, w = parent group error
    vec4 refined_bounds_error; // xyz = refined group center local, w = refined group error (-1.0 se base)
    uvec4 data_offsets;        // x = vertex_offset, y = vertex_count, z = triangle_offset, w = triangle_count
    uvec4 cluster_info;        // x = cluster_id, y = lod_level, z = group_id, w = refined_group
};

struct GPUInstanceData {
    mat4 model_matrix;
    mat4 normal_matrix;
    vec4 bounding_sphere;       // xyz = center mundo, w = radius mundo
    vec4 aabb_min;              // xyz = aabb_min mundo, w = max_screen_error
    vec4 aabb_max;              // xyz = aabb_max mundo, w = lod_mode
    vec4 material_albedo_rough; // rgb = albedo, w = roughness
    vec4 material_metal_spec;   // x = metallic, y = specular, z = material_id, w = forced_lod
    uint instance_id;
    uint mesh_id;
    uint visibility_flags;
    uint resource_generation;
    uint cluster_offset;
    uint cluster_count;
    uint pad0;
    uint pad1;
};

struct VisibleClusterItem {
    uint instance_id;
    uint cluster_id;
};

// 0: Buffer de clusters de geometria compartilhada de todas as malhas registradas
layout(set = 0, binding = 0, std430) readonly buffer InClusters {
    GPUCluster clusters[];
};

// 1: Buffer compacto de pares (instance_id, cluster_id) selecionados na GPU
layout(set = 0, binding = 1, std430) writeonly buffer OutVisibleItems {
    VisibleClusterItem visible_items[];
};

// 2: Buffer de argumentos indiretos (VkDrawIndirectCommand) e contadores de telemetria
layout(set = 0, binding = 2, std430) buffer OutCounterAndDrawArgs {
    uint vertex_count;              // offset 0: 384 (128 triangulos * 3 vertices)
    uint instance_count;            // offset 4: clusters visiveis selecionados
    uint first_vertex;              // offset 8: 0
    uint first_instance;            // offset 12: 0
    uint total_triangles_drawn;     // offset 16: total de triangulos
    uint total_clusters_evaluated;  // offset 20: total de clusters avaliados
    uint max_capacity;              // offset 24: capacidade maxima do buffer de saida
    uint overflow_flag;             // offset 28: 1 se max_capacity foi excedido
};

// 3: Uniforms globais da cena (Camera, Frustum, Viewport)
layout(set = 0, binding = 3, std140) uniform GlobalSceneUniforms {
    mat4 view_proj;
    vec4 frustum_planes[6];
    vec4 camera_pos_fov;        // xyz = camera_pos mundo, w = fov_factor
    vec4 viewport_params;       // x = width, y = height, z = default_max_err, w = default_lod_mode
    uvec4 count_params;         // x = total_instances, y = total_work_items, z = frustum_enable, w = cone_enable
    uvec4 render_params;        // x = shading_mode, y = enable_hiz, z = max_visible_items, w = pad
} ubo;

// 4: Buffer de instâncias globais ativas na cena
layout(set = 0, binding = 4, std430) readonly buffer InInstances {
    GPUInstanceData instances[];
};

// 5: Pirâmide de profundidade Hi-Z (Reversed-Z)
layout(set = 0, binding = 5) uniform sampler2D hiz_depth_pyramid;

// ============================================================================
// TESTES MATEMÁTICOS DE CULLING E DAG (ARB-MATH-V7)
// ============================================================================

bool ARB_GPU_TestFrustum(vec3 center, float radius) {
    for (int i = 0; i < 6; ++i) {
        if (dot(ubo.frustum_planes[i].xyz, center) + ubo.frustum_planes[i].w < -radius) {
            return false;
        }
    }
    return true;
}

bool ARB_GPU_TestConeCull(vec3 center, float radius, vec3 cone_axis, float cutoff) {
    if (cutoff >= 1.0) return true;
    vec3 c_to_cam = center - ubo.camera_pos_fov.xyz;
    float dist = length(c_to_cam);
    return dot(c_to_cam, cone_axis) < (cutoff * dist + radius);
}

float ARB_GPU_ProjectScreenError(vec3 center, float radius, float mesh_error, float vp_height, float fov_factor) {
    float dist = length(center - ubo.camera_pos_fov.xyz);
    float d_eff = max(dist - radius, 0.05);
    return (mesh_error * vp_height) / (2.0 * d_eff * fov_factor);
}

bool ARB_GPU_EvaluateDAGCut(
    vec3 p_center, float p_error,
    vec3 r_center, float r_error, int refined_group_id,
    float vp_height, float fov_factor, float max_screen_err
) {
    bool parent_needed;
    if (p_error > 10000.0) {
        parent_needed = true;
    } else {
        float p_err_px = ARB_GPU_ProjectScreenError(p_center, 0.0, p_error, vp_height, fov_factor);
        parent_needed = (p_err_px > max_screen_err);
    }

    bool child_satisfied = true;
    if (refined_group_id >= 0) {
        float r_err_px = ARB_GPU_ProjectScreenError(r_center, 0.0, r_error, vp_height, fov_factor);
        child_satisfied = (r_err_px <= max_screen_err);
    }

    return parent_needed && child_satisfied;
}

void main() {
    uint g_idx = gl_GlobalInvocationID.x;
    if (g_idx >= ubo.count_params.y) return; // Fora do total_work_items

    atomicAdd(total_clusters_evaluated, 1u);

    // Mapeamento de GlobalInvocationID para (instance_index, local_cluster_index)
    // O buffer de instâncias é percorrido ou indexado
    uint inst_idx = 0;
    uint total_inst = ubo.count_params.x;
    if (total_inst == 0) return;

    // Busca binária rápida ou mapeamento uniforme
    uint curr_acc = 0;
    bool found = false;
    for (uint i = 0; i < total_inst; ++i) {
        uint c_count = instances[i].cluster_count;
        if (g_idx >= curr_acc && g_idx < curr_acc + c_count) {
            inst_idx = i;
            found = true;
            break;
        }
        curr_acc += c_count;
    }
    if (!found) return;

    GPUInstanceData inst = instances[inst_idx];
    if ((inst.visibility_flags & 1u) == 0u) return;

    // 1. Frustum Culling em nível de Instância
    if (ubo.count_params.z != 0u) {
        if (!ARB_GPU_TestFrustum(inst.bounding_sphere.xyz, inst.bounding_sphere.w)) {
            return;
        }
    }

    uint local_cluster_idx = g_idx - curr_acc;
    uint global_cluster_idx = inst.cluster_offset + local_cluster_idx;
    GPUCluster c = clusters[global_cluster_idx];

    // Transforma centro do cluster para espaço de mundo usando model_matrix da instância
    vec4 world_c4 = inst.model_matrix * vec4(c.center_radius.xyz, 1.0);
    vec3 world_center = world_c4.xyz;

    // Escala máxima do bounding sphere sob transformações não-uniformes
    float sx = length(inst.model_matrix[0].xyz);
    float sy = length(inst.model_matrix[1].xyz);
    float sz = length(inst.model_matrix[2].xyz);
    float max_scale = max(sx, max(sy, sz));
    float world_radius = c.center_radius.w * max_scale;

    // 2. Frustum Culling em nível de Cluster
    if (ubo.count_params.z != 0u) {
        if (!ARB_GPU_TestFrustum(world_center, world_radius)) {
            return;
        }
    }

    // 3. Normal Cone Backface Culling
    if (ubo.count_params.w != 0u) {
        vec3 world_cone_axis = normalize(mat3(inst.normal_matrix) * c.cone_axis_cutoff.xyz);
        if ((inst.visibility_flags & 4u) != 0u) {
            world_cone_axis = -world_cone_axis;
        }
        if (!ARB_GPU_TestConeCull(world_center, world_radius, world_cone_axis, c.cone_axis_cutoff.w)) {
            return;
        }
    }

    // 4. DAG LOD Selection
    bool is_selected = false;
    uint lod_mode = uint(inst.aabb_max.w);
    float max_screen_err = inst.aabb_min.w;
    if (max_screen_err < 0.1) max_screen_err = ubo.viewport_params.z;

    if (lod_mode == 1u) {
        // Modo Forçado
        uint forced_lod = uint(inst.material_metal_spec.w);
        if (c.cluster_info.y == forced_lod) {
            is_selected = true;
        }
    } else {
        // Auto DAG por Projeção Perspectiva de Erro
        float fov_factor = max(ubo.camera_pos_fov.w, 0.1);
        float vp_h = max(ubo.viewport_params.y, 1.0);

        vec3 p_center_world = (inst.model_matrix * vec4(c.group_bounds_error.xyz, 1.0)).xyz;
        vec3 r_center_world = (inst.model_matrix * vec4(c.refined_bounds_error.xyz, 1.0)).xyz;

        is_selected = ARB_GPU_EvaluateDAGCut(
            p_center_world, c.group_bounds_error.w * max_scale,
            r_center_world, c.refined_bounds_error.w * max_scale, int(c.cluster_info.w),
            vp_h, fov_factor, max_screen_err
        );
    }

    if (is_selected) {
        uint slot = atomicAdd(instance_count, 1u);
        if (slot < max_capacity) {
            visible_items[slot].instance_id = inst_idx;
            visible_items[slot].cluster_id = global_cluster_idx;
            atomicAdd(total_triangles_drawn, c.data_offsets.w);
        } else {
            overflow_flag = 1u;
        }
    }
}
