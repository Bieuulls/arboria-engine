#[compute]
#version 450

#extension GL_KHR_shader_subgroup_basic : enable
#extension GL_KHR_shader_subgroup_ballot : enable
#extension GL_KHR_shader_subgroup_arithmetic : enable

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
    uvec4 render_params;        // x = shading_mode, y = enable_hiz, z = max_visible_items, w = wind_enabled
    vec4 wind_params;           // x = time, y = strength, z = freq, w = gust
    vec4 wind_direction;        // xyz = dir_norm, w = unused
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

// [ARB_MATH_05] Teste de Oclusão Hi-Z Hierárquico em Reversed-Z (Vulkan 1.4)
bool ARB_GPU_TestHiZOcclusion(vec3 center, float radius) {
    vec3 c_to_cam = ubo.camera_pos_fov.xyz - center;
    float dist = length(c_to_cam);

    // Se a câmera estiver dentro da esfera do cluster ou cruzando o near plane, nunca ocluir (conservador)
    if (dist <= radius + 0.1) return true;

    vec4 clip_center = ubo.view_proj * vec4(center, 1.0);
    if (clip_center.w - radius <= 0.05) return true; // Near clip guard

    vec2 vp = ubo.viewport_params.xy;
    vec3 v_norm = c_to_cam / dist;

    // Vetores ortogonais à linha de visão para obter os 4 pontos de silhueta extrema
    vec3 up_guide = (abs(v_norm.y) < 0.99) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 right_vec = normalize(cross(up_guide, v_norm));
    vec3 up_vec = cross(v_norm, right_vec);

    // 4 pontos extremos no horizonte da esfera
    vec4 cp0 = ubo.view_proj * vec4(center - right_vec * radius, 1.0);
    vec4 cp1 = ubo.view_proj * vec4(center + right_vec * radius, 1.0);
    vec4 cp2 = ubo.view_proj * vec4(center - up_vec * radius, 1.0);
    vec4 cp3 = ubo.view_proj * vec4(center + up_vec * radius, 1.0);

    if (cp0.w <= 0.0 || cp1.w <= 0.0 || cp2.w <= 0.0 || cp3.w <= 0.0) return true;

    vec2 s0 = (cp0.xy / cp0.w * 0.5 + 0.5) * vp;
    vec2 s1 = (cp1.xy / cp1.w * 0.5 + 0.5) * vp;
    vec2 s2 = (cp2.xy / cp2.w * 0.5 + 0.5) * vp;
    vec2 s3 = (cp3.xy / cp3.w * 0.5 + 0.5) * vp;

    vec2 bbox_min = clamp(min(min(s0, s1), min(s2, s3)), vec2(0.0), vp);
    vec2 bbox_max = clamp(max(max(s0, s1), max(s2, s3)), vec2(0.0), vp);
    vec2 bbox_size = bbox_max - bbox_min;

    float max_dim = max(bbox_size.x, bbox_size.y);
    if (max_dim < 1.0) return true; // Conservador para micropolígonos

    float mip = clamp(ceil(log2(max_dim)), 0.0, 10.0);
    vec2 uv_min = bbox_min / vp;
    vec2 uv_max = bbox_max / vp;

    float d0 = textureLod(hiz_depth_pyramid, uv_min, mip).r;
    float d1 = textureLod(hiz_depth_pyramid, vec2(uv_max.x, uv_min.y), mip).r;
    float d2 = textureLod(hiz_depth_pyramid, vec2(uv_min.x, uv_max.y), mip).r;
    float d3 = textureLod(hiz_depth_pyramid, uv_max, mip).r;

    float ocl_furthest_z = min(min(d0, d1), min(d2, d3));

    // Ponto mais próximo da câmera na esfera do cluster
    vec3 closest_pt = center + v_norm * min(radius, dist * 0.95);
    vec4 clip_closest = ubo.view_proj * vec4(closest_pt, 1.0);
    if (clip_closest.w <= 0.0) return true;
    float cluster_closest_z = clamp(clip_closest.z / clip_closest.w, 0.0, 1.0);

    // Em Reversed-Z: se o ponto mais próximo do cluster for menor que a profundidade do oclusor,
    // o cluster está totalmente oculto
    return (cluster_closest_z >= ocl_furthest_z);
}

void main() {
    uint g_idx = gl_GlobalInvocationID.x;
    bool in_bounds = (g_idx < ubo.count_params.y);

    // Agregação atômica no Subgroup para total_clusters_evaluated (redução de 32x no tráfego L2/VRAM)
    uint eval_count = subgroupAdd(in_bounds ? 1u : 0u);
    if (subgroupElect() && eval_count > 0u) {
        atomicAdd(total_clusters_evaluated, eval_count);
    }

    bool is_selected = false;
    uint tri_count = 0u;
    uint out_inst_idx = 0u;
    uint out_cluster_idx = 0u;

    if (in_bounds) {
        uint total_inst = ubo.count_params.x;
        uint c_count = instances[0].cluster_count;
        if (total_inst > 0u && c_count > 0u) {
            uint inst_idx = g_idx / c_count;
            if (inst_idx < total_inst) {
                GPUInstanceData inst = instances[inst_idx];
                if ((inst.visibility_flags & 1u) != 0u) {
                    uint lod_mode = uint(inst.aabb_max.w);
                    if (lod_mode == 1u) {
                        // LOD Forçado: Paridade geométrica estrita com malha original
                        uint forced_lod = uint(inst.material_metal_spec.w);
                        uint local_cluster_idx = g_idx % c_count;
                        uint global_cluster_idx = inst.cluster_offset + local_cluster_idx;
                        GPUCluster c = clusters[global_cluster_idx];
                        if (c.cluster_info.y == forced_lod) {
                            is_selected = true;
                            tri_count = c.data_offsets.w;
                            out_inst_idx = inst_idx;
                            out_cluster_idx = global_cluster_idx;
                        }
                    } else {
                        bool inst_visible = true;
                        if (ubo.count_params.z != 0u) {
                            inst_visible = ARB_GPU_TestFrustum(inst.bounding_sphere.xyz, inst.bounding_sphere.w);
                        }

                        if (inst_visible) {
                            uint local_cluster_idx = g_idx % c_count;
                            uint global_cluster_idx = inst.cluster_offset + local_cluster_idx;
                            GPUCluster c = clusters[global_cluster_idx];

                            vec4 world_c4 = inst.model_matrix * vec4(c.center_radius.xyz, 1.0);
                            vec3 world_center = world_c4.xyz;

                            float sx = length(inst.model_matrix[0].xyz);
                            float sy = length(inst.model_matrix[1].xyz);
                            float sz = length(inst.model_matrix[2].xyz);
                            float max_scale = max(sx, max(sy, sz));
                            float world_radius = c.center_radius.w * max_scale;

                            bool cluster_visible = true;

                            // 2. Frustum Culling em nível de Cluster
                            if (ubo.count_params.z != 0u) {
                                cluster_visible = ARB_GPU_TestFrustum(world_center, world_radius);
                            }

                            // 3. Normal Cone Backface Culling
                            if (cluster_visible && ubo.count_params.w != 0u) {
                                vec3 world_cone_axis = normalize(mat3(inst.normal_matrix) * c.cone_axis_cutoff.xyz);
                                if ((inst.visibility_flags & 4u) != 0u) {
                                    world_cone_axis = -world_cone_axis;
                                }
                                cluster_visible = ARB_GPU_TestConeCull(world_center, world_radius, world_cone_axis, c.cone_axis_cutoff.w);
                            }

                            // 4. Hi-Z Occlusion Culling
                            if (cluster_visible && ubo.render_params.y != 0u) {
                                cluster_visible = ARB_GPU_TestHiZOcclusion(world_center, world_radius);
                            }

                            // 5. DAG LOD Selection
                            if (cluster_visible) {
                                float max_screen_err = inst.aabb_min.w;
                                if (max_screen_err < 0.1) max_screen_err = ubo.viewport_params.z;

                                float fov_factor = max(ubo.camera_pos_fov.w, 0.1);
                                float vp_h = max(ubo.viewport_params.y, 1.0);

                                vec3 p_center_world = (inst.model_matrix * vec4(c.group_bounds_error.xyz, 1.0)).xyz;
                                vec3 r_center_world = (inst.model_matrix * vec4(c.refined_bounds_error.xyz, 1.0)).xyz;

                                is_selected = ARB_GPU_EvaluateDAGCut(
                                    p_center_world, c.group_bounds_error.w * max_scale,
                                    r_center_world, c.refined_bounds_error.w * max_scale, int(c.cluster_info.w),
                                    vp_h, fov_factor, max_screen_err
                                );

                                if (is_selected) {
                                    tri_count = c.data_offsets.w;
                                    out_inst_idx = inst_idx;
                                    out_cluster_idx = global_cluster_idx;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ========================================================================
    // ALOCAÇÃO ATÔMICA MASTER VIA SUBGROUP / WAVE INTRINSICS (ZERO CONTENÇÃO)
    // ========================================================================
    uvec4 selected_ballot = subgroupBallot(is_selected);
    uint subgroup_selected_count = subgroupBallotBitCount(selected_ballot);

    uint base_slot = 0u;
    if (subgroupElect() && subgroup_selected_count > 0u) {
        base_slot = atomicAdd(instance_count, subgroup_selected_count);
        if (base_slot + subgroup_selected_count > max_capacity) {
            overflow_flag = 1u;
        }
    }
    base_slot = subgroupBroadcastFirst(base_slot);

    if (is_selected) {
        uint local_idx = subgroupBallotExclusiveBitCount(selected_ballot);
        uint final_slot = base_slot + local_idx;
        if (final_slot < max_capacity) {
            visible_items[final_slot].instance_id = out_inst_idx;
            visible_items[final_slot].cluster_id = out_cluster_idx;
        }
    }

    uint subgroup_tris = subgroupAdd(tri_count);
    if (subgroupElect() && subgroup_tris > 0u) {
        atomicAdd(total_triangles_drawn, subgroup_tris);
    }
}
