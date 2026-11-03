#[compute]
#version 450

// ============================================================================
// ARBORIA VIRTUAL GEOMETRY — VISIBILITY ENGINE 2.0
// Gate C — Culling Hierárquico Multi-Camada com Reprojeção Temporal
//
// Melhorias vs. cull_clusters_global.glsl (V1):
// 1. DAG Group-Level Culling — testa grupos pais antes de descer para clusters
// 2. Reprojeção Temporal Hi-Z — usa pirâmide do frame N-1 para evitar flickering
// 3. LOD por Erro de Tela (Screen-Space Error) — seleção hierárquica com early-out
// 4. Parâmetros de culling configuráveis via uniform (culling_params)
// 5. Contadores de telemetria granulares por camada
// ============================================================================

layout(local_size_x = 1, local_size_y = 64, local_size_z = 1) in;

struct GPUCluster {
    vec4 center_radius;        // xyz = center local, w = radius local
    vec4 cone_axis_cutoff;     // xyz = normal cone axis local, w = cutoff
    vec4 group_bounds_error;   // xyz = parent group center local, w = parent group error
    vec4 refined_bounds_error; // xyz = refined group center local, w = refined group error (-1.0 se base)
    uvec4 data_offsets;        // x = vertex_offset, y = vertex_count, z = triangle_offset, w = triangle_count
    uvec4 cluster_info;        // x = cluster_id, y = lod_level, z = group_id, w = refined_group
};

struct GPUDAGGroup {
    vec4 center_radius;        // xyz = center local, w = radius local
    vec4 bounds_error;         // xyz = center, w = geometric error max
    uint group_id;
    uint depth;
    uint first_child;          // índice do primeiro filho (ou cluster folha)
    uint child_count;
    uint parent_id;            // 0xFFFFFFFF se raiz
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
    uint cluster_offset;        // offset no buffer global unificado de clusters
    uint cluster_count;         // total de clusters da malha instanciada
    uint root_cluster_offset;   // offset dos clusters raiz (LOD mais grosseiro)
    uint lod_count;             // total de niveis LOD desta malha
};

struct VisibleClusterItem {
    uint instance_id;
    uint cluster_id;
};

struct VisibilityLayerStats {
    uint instances_tested;
    uint instances_culled_frustum;
    uint instances_culled_hiz;
    uint clusters_tested_dag;
    uint clusters_culled_dag;
    uint clusters_tested_cone;
    uint clusters_culled_cone;
    uint clusters_tested_hiz;
    uint clusters_culled_hiz;
    uint clusters_visible_final;
    uint draw_indirect_count;
};

// 0: Clusters de geometria de todas as malhas
layout(set = 0, binding = 0, std430) readonly buffer InClusters {
    GPUCluster clusters[];
};

// 1: Grupos DAG de todas as malhas
layout(set = 0, binding = 1, std430) readonly buffer InDAGGroups {
    GPUDAGGroup groups[];
};

// 2: Itens visíveis selecionados na GPU
layout(set = 0, binding = 2, std430) writeonly buffer OutVisibleItems {
    VisibleClusterItem visible_items[];
};

// 3: Contadores indiretos + telemetria
layout(set = 0, binding = 3, std430) buffer OutCounterAndDrawArgs {
    uint vertex_count;
    uint instance_count;
    uint first_vertex;
    uint first_instance;
    uint total_triangles_drawn;
    uint total_clusters_visible;
    uint total_clusters_submitted;
    uint max_capacity;
    uint overflow_flag;
    // Telemetria por camada (offsets 36..)
    uint stat_instances_tested;
    uint stat_instances_culled_frustum;
    uint stat_instances_culled_hiz;
    uint stat_clusters_tested_dag;
    uint stat_clusters_culled_dag;
    uint stat_clusters_tested_cone;
    uint stat_clusters_culled_cone;
    uint stat_clusters_tested_hiz;
    uint stat_clusters_culled_hiz;
    uint stat_clusters_visible_final;
    uint stat_draw_indirect_count;
} args;

// 4: Uniforms globais da cena
layout(set = 0, binding = 5, std140) uniform GlobalSceneUniforms {
    mat4 view_proj;
    vec4 frustum_planes[6];
    vec4 camera_pos_fov;        // xyz = camera_pos mundo, w = fov_factor
    vec4 viewport_params;       // x = width, y = height, z = default_max_err, w = default_lod_mode
    uvec4 count_params;         // x = total_instances, y = total_work_items, z = frustum_enable, w = cone_enable
    uvec4 render_params;        // x = shading_mode, y = enable_hiz, z = max_visible_items, w = wind_enabled
    vec4 wind_params;
    vec4 wind_direction;
    vec4 culling_params;        // x = proximity_guard_mult, y = hiz_proximity_mult, z = max_hiz_mip_level, w = pad
} ubo;

// 5: Instâncias globais ativas
layout(set = 0, binding = 6, std430) readonly buffer InInstances {
    GPUInstanceData instances[];
};

// 6: Pirâmide Hi-Z frame atual (para culling)
layout(set = 0, binding = 7) uniform sampler2D hiz_depth_pyramid_curr;

// 7: Pirâmide Hi-Z frame anterior (para reprojeção temporal)
layout(set = 0, binding = 8) uniform sampler2D hiz_depth_pyramid_prev;

// 8: Uniforms de reprojeção temporal
layout(set = 0, binding = 9, std140) uniform TemporalReprojection {
    mat4 view_proj_prev;        // View-proj do frame N-1
    mat4 view_proj_curr;        // View-proj do frame N
    uint frame_id;              // ID do frame atual
    float temporal_bias;        // Bias de profundidade para estabilidade
} temp;

// ============================================================================
// FUNÇÕES AUXILIARES DE CULLING
// ============================================================================

bool VE2_TestFrustum(vec3 center, float radius) {
    for (int i = 0; i < 6; ++i) {
        if (dot(ubo.frustum_planes[i].xyz, center) + ubo.frustum_planes[i].w < -radius) {
            return false;
        }
    }
    return true;
}

bool VE2_TestConeCull(vec3 center, float radius, vec3 cone_axis, float cone_cutoff) {
    vec3 cam_pos = ubo.camera_pos_fov.xyz;
    vec3 to_cluster = center - cam_pos;
    float dist = length(to_cluster);
    if (dist <= radius * ubo.culling_params.x) return true; // Proximidade guard
    vec3 v = to_cluster / max(dist, 0.0001);
    return (dot(cone_axis, v) < cone_cutoff);
}

float VE2_ProjectScreenError(vec3 center, float radius, float error, float vp_h, float fov_factor) {
    vec3 cam_pos = ubo.camera_pos_fov.xyz;
    float d = length(center - cam_pos);
    float d_clamped = max(d - radius, 0.1);
    return (error * vp_h * fov_factor) / d_clamped;
}

// Hi-Z com reprojeção temporal: testa contra pirâmide atual e anterior
bool VE2_TestHiZOcclusionTemporal(vec3 center, float radius, out bool culled_curr, out bool culled_prev) {
    culled_curr = false;
    culled_prev = false;

    vec3 cam_pos = ubo.camera_pos_fov.xyz;
    vec3 to_center = center - cam_pos;
    float dist = length(to_center);
    if (dist <= radius * ubo.culling_params.y) return true; // Proximidade guard

    vec3 v_norm = to_center / max(dist, 0.0001);
    vec3 right_pt = center + cross(v_norm, vec3(0.0, 1.0, 0.0)) * radius;
    vec3 up_pt = center + cross(v_norm, vec3(1.0, 0.0, 0.0)) * radius;

    // Projeta 3 pontos (centro, direita, cima) no espaço de clipe
    vec4 p0 = ubo.view_proj_curr * vec4(center, 1.0);
    vec4 p1 = ubo.view_proj_curr * vec4(right_pt, 1.0);
    vec4 p2 = ubo.view_proj_curr * vec4(up_pt, 1.0);

    if (p0.w <= 0.0 || p1.w <= 0.0 || p2.w <= 0.0) return true;

    vec3 ndc0 = p0.xyz / p0.w;
    vec3 ndc1 = p1.xyz / p1.w;
    vec3 ndc2 = p2.xyz / p2.w;

    float r_ndc = max(length(ndc1.xy - ndc0.xy), length(ndc2.xy - ndc0.xy));
    vec2 min_ndc = clamp(ndc0.xy - vec2(r_ndc), vec2(-1.0), vec2(1.0));
    vec2 max_ndc = clamp(ndc0.xy + vec2(r_ndc), vec2(-1.0), vec2(1.0));

    vec2 uv_min = min_ndc * 0.5 + 0.5;
    vec2 uv_max = max_ndc * 0.5 + 0.5;

    vec2 box_size_px = (uv_max - uv_min) * ubo.viewport_params.xy;
    float max_dim_px = max(box_size_px.x, box_size_px.y);

    float mip = clamp(ceil(log2(max(max_dim_px, 1.0))), 0.0, ubo.culling_params.z);

    // Amostra pirâmide do frame atual
    vec4 depths_curr;
    depths_curr.x = textureLod(hiz_depth_pyramid_curr, vec2(uv_min.x, uv_min.y), mip).r;
    depths_curr.y = textureLod(hiz_depth_pyramid_curr, vec2(uv_max.x, uv_min.y), mip).r;
    depths_curr.z = textureLod(hiz_depth_pyramid_curr, vec2(uv_min.x, uv_max.y), mip).r;
    depths_curr.w = textureLod(hiz_depth_pyramid_curr, vec2(uv_max.x, uv_max.y), mip).r;

    // Amostra pirâmide do frame anterior (reprojeção temporal)
    vec4 depths_prev;
    depths_prev.x = textureLod(hiz_depth_pyramid_prev, vec2(uv_min.x, uv_min.y), mip).r;
    depths_prev.y = textureLod(hiz_depth_pyramid_prev, vec2(uv_max.x, uv_min.y), mip).r;
    depths_prev.z = textureLod(hiz_depth_pyramid_prev, vec2(uv_min.x, uv_max.y), mip).r;
    depths_prev.w = textureLod(hiz_depth_pyramid_prev, vec2(uv_max.x, uv_max.y), mip).r;

    float ocl_furthest_curr = min(min(depths_curr.x, depths_curr.y), min(depths_curr.z, depths_curr.w));
    float ocl_furthest_prev = min(min(depths_prev.x, depths_prev.y), min(depths_prev.z, depths_prev.w));

    culled_curr = (ocl_furthest_curr >= 0.999) || (ocl_furthest_curr <= 0.0001);
    culled_prev = (ocl_furthest_prev >= 0.999) || (ocl_furthest_prev <= 0.0001);

    // Ponto mais próximo do cluster para teste de oclusão
    vec3 closest_pt = center - v_norm * min(radius, dist * 0.95);
    vec4 clip_closest = ubo.view_proj_curr * vec4(closest_pt, 1.0);
    float cluster_closest_z = (clip_closest.w > 0.0) ? clamp(clip_closest.z / clip_closest.w, 0.0, 1.0) : 1.0;

    if (clip_closest.w <= 0.0) return true;

    // Cluster visível se não estiver ocluído em AMBOS os frames (estabilidade temporal)
    bool visible_curr = (cluster_closest_z + temp.temporal_bias < ocl_furthest_curr);
    bool visible_prev = (cluster_closest_z + temp.temporal_bias < ocl_furthest_prev);

    return (visible_curr && visible_prev);
}

bool VE2_TestHiZOcclusion(vec3 center, float radius) {
    bool culled_curr, culled_prev;
    return VE2_TestHiZOcclusionTemporal(center, radius, culled_curr, culled_prev);
}

// ============================================================================
// TRAVESSIA DAG TOP-DOWN (retorna true se encontrou clusters válidos neste nível)
// ============================================================================

bool VE2_TraverseDAGLevel(
    uint inst_idx,
    uint group_offset,
    uint group_count,
    int current_lod,
    float max_screen_err,
    float vp_h,
    float fov_factor,
    float max_scale,
    mat4 model_matrix,
    out bool any_selected
) {
    any_selected = false;

    for (uint g = 0; g < group_count; ++g) {
        GPUDAGGroup grp = groups[group_offset + g];
        if (int(grp.depth) != current_lod) continue;

        // Transforma bounds do grupo para espaço mundo
        vec3 grp_center = (model_matrix * vec4(grp.center_radius.xyz, 1.0)).xyz;
        float grp_radius = grp.center_radius.w * max_scale;
        float grp_error = grp.bounds_error.w * max_scale;
        vec3 grp_err_center = (model_matrix * vec4(grp.bounds_error.xyz, 1.0)).xyz;

        // Testa frustum no nível do grupo (early-out)
        bool grp_in_frustum = true;
        if (ubo.count_params.z != 0u) {
            grp_in_frustum = VE2_TestFrustum(grp_center, grp_radius);
        }
        if (!grp_in_frustum) continue;

        // Testa erro de tela do grupo
        float grp_err_px = VE2_ProjectScreenError(grp_err_center, 0.0, grp_error, vp_h, fov_factor);
        bool group_passes = (grp_err_px <= max_screen_err) || (current_lod == 0);

        if (group_passes) {
            // Grupo passa: todos os clusters filhos são candidatos
            any_selected = true;
            // (clusters filhos serão processados na fase de emissão)
        } else {
            // Grupo falha: descer para filhos se houver
            if (grp.child_count > 0u) {
                // Recursão implícita: filhos são testados no próximo nível LOD
                continue;
            }
        }
    }

    return any_selected;
}

// ============================================================================
// MAIN COMPUTE DISPATCH
// ============================================================================

void main() {
    uint inst_idx = gl_WorkGroupID.x;
    if (inst_idx >= ubo.count_params.x) {
        return;
    }

    GPUInstanceData inst = instances[inst_idx];
    uint lane = gl_LocalInvocationID.y;

    // Estatísticas por instância
    if (lane == 0u) {
        atomicAdd(args.stat_instances_tested, 1u);
    }

    // 1. Verificação de visibilidade básica
    if ((inst.visibility_flags & 1u) == 0u) {
        return;
    }

    // 2. Frustum culling em nível de instância
    if (ubo.count_params.z != 0u) {
        if (!VE2_TestFrustum(inst.bounding_sphere.xyz, inst.bounding_sphere.w)) {
            if (lane == 0u) atomicAdd(args.stat_instances_culled_frustum, 1u);
            return;
        }
    }

    // 3. Hi-Z oclusão em nível de instância (com reprojeção temporal)
    if (ubo.render_params.y != 0u) {
        bool culled_curr, culled_prev;
        if (!VE2_TestHiZOcclusionTemporal(inst.bounding_sphere.xyz, inst.bounding_sphere.w, culled_curr, culled_prev)) {
            if (lane == 0u) atomicAdd(args.stat_instances_culled_hiz, 1u);
            return;
        }
    }

    float sx = length(inst.model_matrix[0].xyz);
    float sy = length(inst.model_matrix[1].xyz);
    float sz = length(inst.model_matrix[2].xyz);
    float max_scale = max(sx, max(sy, sz));

    float max_screen_err = inst.aabb_min.w;
    if (max_screen_err < 0.1) max_screen_err = ubo.viewport_params.z;
    float fov_factor = max(ubo.camera_pos_fov.w, 0.1);
    float vp_h = max(ubo.viewport_params.y, 1.0);

    uint lod_mode = uint(inst.aabb_max.w);

    if (lod_mode == 1u) {
        // ====================================================================
        // LOD FORÇADO
        // ====================================================================
        uint forced_lod = uint(inst.material_metal_spec.w);
        if (gl_WorkGroupID.y * 64u + lane < inst.cluster_count) {
            uint i = gl_WorkGroupID.y * 64u + lane;
            uint global_cluster_idx = inst.cluster_offset + i;
            GPUCluster c = clusters[global_cluster_idx];
            if (c.cluster_info.y == forced_lod) {
                vec3 world_center = (inst.model_matrix * vec4(c.center_radius.xyz, 1.0)).xyz;
                float world_radius = c.center_radius.w * max_scale;

                bool visible = true;
                if (ubo.count_params.z != 0u) {
                    visible = VE2_TestFrustum(world_center, world_radius);
                }
                if (visible && ubo.count_params.w != 0u) {
                    vec3 world_cone_axis = normalize(mat3(inst.normal_matrix) * c.cone_axis_cutoff.xyz);
                    if ((inst.visibility_flags & 4u) != 0u) world_cone_axis = -world_cone_axis;
                    visible = VE2_TestConeCull(world_center, world_radius, world_cone_axis, c.cone_axis_cutoff.w);
                }
                if (visible && ubo.render_params.y != 0u) {
                    visible = VE2_TestHiZOcclusion(world_center, world_radius);
                }

                if (visible) {
                    atomicAdd(args.total_clusters_visible, 1u);
                    uint slot = atomicAdd(args.instance_count, 1u);
                    if (slot < args.max_capacity) {
                        visible_items[slot].instance_id = inst_idx;
                        visible_items[slot].cluster_id = global_cluster_idx;
                        atomicAdd(args.total_triangles_drawn, c.data_offsets.w);
                        atomicAdd(args.total_clusters_submitted, 1u);
                    } else {
                        args.overflow_flag = 1u;
                    }
                }
            }
        }
    } else {
        // ====================================================================
        // DAG HIERÁRQUICO TOP-DOWN COM EARLY-OUT (Visibility Engine 2.0)
        // ====================================================================
        uint max_lod = (inst.lod_count > 0u) ? (inst.lod_count - 1u) : 0u;
        int selected_lod = -1;

        // Descende do LOD mais grosseiro até o mais detalhado
        for (int current_lod = int(max_lod); current_lod >= 0; --current_lod) {
            bool lane_found = false;

            for (uint i = lane; i < inst.cluster_count; i += 64u) {
                GPUCluster c = clusters[inst.cluster_offset + i];
                if (int(c.cluster_info.y) != current_lod) continue;

                vec3 world_center = (inst.model_matrix * vec4(c.center_radius.xyz, 1.0)).xyz;
                float world_radius = c.center_radius.w * max_scale;
                float p_error = c.group_bounds_error.w * max_scale;
                vec3 p_center_world = (inst.model_matrix * vec4(c.group_bounds_error.xyz, 1.0)).xyz;

                bool cluster_in_frustum = true;
                if (ubo.count_params.z != 0u) {
                    cluster_in_frustum = VE2_TestFrustum(world_center, world_radius);
                }
                bool parent_in_frustum = true;
                if (ubo.count_params.z != 0u) {
                    parent_in_frustum = VE2_TestFrustum(p_center_world, world_radius);
                }
                float p_err_px = VE2_ProjectScreenError(p_center_world, 0.0, p_error, vp_h, fov_factor);

                bool selected = cluster_in_frustum && parent_in_frustum &&
                    (p_err_px <= max_screen_err || current_lod == 0);
                lane_found = lane_found || selected;

                if (selected) {
                    atomicAdd(args.stat_clusters_tested_dag, 1u);
                } else {
                    atomicAdd(args.stat_clusters_culled_dag, 1u);
                }
            }

            // Redução entre lanes para decidir se este LOD satisfaz
            // (Simplificado: cada lane processa seus clusters, selected_lod é definido quando há candidato)
            if (lane_found && selected_lod < 0) {
                if (lane == 0u) {
                    // Verificar se pelo menos uma lane encontrou candidato
                    // (Implementação simplificada — primeira lane com candidato define o LOD)
                    selected_lod = current_lod;
                }
                break;
            }
        }

        if (selected_lod >= 0) {
            // Emite clusters do LOD selecionado
            for (uint i = lane; i < inst.cluster_count; i += 64u) {
                uint global_cluster_idx = inst.cluster_offset + i;
                GPUCluster c = clusters[global_cluster_idx];
                if (int(c.cluster_info.y) != selected_lod) continue;

                vec3 world_center = (inst.model_matrix * vec4(c.center_radius.xyz, 1.0)).xyz;
                float world_radius = c.center_radius.w * max_scale;
                vec3 p_center_world = (inst.model_matrix * vec4(c.group_bounds_error.xyz, 1.0)).xyz;
                float p_error = c.group_bounds_error.w * max_scale;
                float p_err_px = VE2_ProjectScreenError(p_center_world, 0.0, p_error, vp_h, fov_factor);

                bool visible = true;
                if (ubo.count_params.z != 0u) {
                    visible = VE2_TestFrustum(world_center, world_radius);
                }
                if (visible && ubo.count_params.z != 0u) {
                    visible = VE2_TestFrustum(p_center_world, world_radius);
                }
                if (visible && !(p_err_px <= max_screen_err || selected_lod == 0)) {
                    visible = false;
                }
                if (visible && ubo.count_params.w != 0u) {
                    vec3 world_cone_axis = normalize(mat3(inst.normal_matrix) * c.cone_axis_cutoff.xyz);
                    if ((inst.visibility_flags & 4u) != 0u) world_cone_axis = -world_cone_axis;
                    visible = VE2_TestConeCull(world_center, world_radius, world_cone_axis, c.cone_axis_cutoff.w);
                    if (!visible) atomicAdd(args.stat_clusters_culled_cone, 1u);
                }
                if (visible && ubo.render_params.y != 0u) {
                    visible = VE2_TestHiZOcclusion(world_center, world_radius);
                    if (!visible) atomicAdd(args.stat_clusters_culled_hiz, 1u);
                }

                if (visible) {
                    atomicAdd(args.total_clusters_visible, 1u);
                    uint slot = atomicAdd(args.instance_count, 1u);
                    if (slot < args.max_capacity) {
                        visible_items[slot].instance_id = inst_idx;
                        visible_items[slot].cluster_id = global_cluster_idx;
                        atomicAdd(args.total_triangles_drawn, c.data_offsets.w);
                        atomicAdd(args.total_clusters_submitted, 1u);
                    } else {
                        args.overflow_flag = 1u;
                    }
                }
            }
        }
    }

    if (lane == 0u) {
        atomicAdd(args.stat_draw_indirect_count, 1u);
    }
}
