#[compute]
#version 450

// ============================================================================
// ARBORIA VIRTUAL GEOMETRY — GPU SCENE GLOBAL CLUSTER CULLING & HIERARCHICAL DAG
// Arquitetura Global Batelada Verdadeira:
// - 1 ÚNICO Compute Dispatch para TODA a cena (independente de tipos de malha)
// - Travessia Hierárquica Top-Down do DAG com Early-Out
// - Layout Binário Estrito std430 compatível com arboria_gpu_scene_types.h
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
    uint cluster_offset;        // offset no buffer global unificado de clusters
    uint cluster_count;         // total de clusters da malha instanciada
    uint root_cluster_offset;   // offset dos clusters raiz (LOD mais grosseiro)
    uint lod_count;             // total de niveis LOD desta malha
};

struct VisibleClusterItem {
    uint instance_id;
    uint cluster_id;
};

// 0: Buffer unificado de clusters de geometria de todas as malhas da cena
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

// 4: Buffer de instâncias globais ativas na cena (todas as instâncias de todas as malhas)
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

bool ARB_GPU_TestConeCull(vec3 center, float radius, vec3 cone_axis, float cone_cutoff) {
    vec3 cam_pos = ubo.camera_pos_fov.xyz;
    vec3 to_cluster = center - cam_pos;
    float dist = length(to_cluster);
    if (dist <= radius * 2.5) return true; // Proximidade guard
    vec3 v = to_cluster / max(dist, 0.0001);
    return (dot(cone_axis, v) < cone_cutoff);
}

float ARB_GPU_ProjectScreenError(vec3 center, float radius, float error, float vp_h, float fov_factor) {
    vec3 cam_pos = ubo.camera_pos_fov.xyz;
    float d = length(center - cam_pos);
    float d_clamped = max(d - radius, 0.1);
    return (error * vp_h * fov_factor) / d_clamped;
}

bool ARB_GPU_TestHiZOcclusion(vec3 center, float radius) {
    vec3 cam_pos = ubo.camera_pos_fov.xyz;
    vec3 to_center = center - cam_pos;
    float dist = length(to_center);
    if (dist <= radius * 2.0) return true;

    vec3 v_norm = to_center / max(dist, 0.0001);
    vec3 right_pt = center + cross(v_norm, vec3(0.0, 1.0, 0.0)) * radius;
    vec3 up_pt    = center + cross(v_norm, vec3(1.0, 0.0, 0.0)) * radius;

    vec4 p0 = ubo.view_proj * vec4(center, 1.0);
    vec4 p1 = ubo.view_proj * vec4(right_pt, 1.0);
    vec4 p2 = ubo.view_proj * vec4(up_pt, 1.0);

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

    float mip = clamp(ceil(log2(max(max_dim_px, 1.0))), 0.0, 11.0);

    vec4 depths;
    depths.x = textureLod(hiz_depth_pyramid, vec2(uv_min.x, uv_min.y), mip).r;
    depths.y = textureLod(hiz_depth_pyramid, vec2(uv_max.x, uv_min.y), mip).r;
    depths.z = textureLod(hiz_depth_pyramid, vec2(uv_min.x, uv_max.y), mip).r;
    depths.w = textureLod(hiz_depth_pyramid, vec2(uv_max.x, uv_max.y), mip).r;

    float ocl_furthest_z = min(min(depths.x, depths.y), min(depths.z, depths.w));
    if (ocl_furthest_z >= 0.999 || ocl_furthest_z <= 0.0001) return true;

    vec3 closest_pt = center - v_norm * min(radius, dist * 0.95);
    vec4 clip_closest = ubo.view_proj * vec4(closest_pt, 1.0);
    if (clip_closest.w <= 0.0) return true;
    float cluster_closest_z = clamp(clip_closest.z / clip_closest.w, 0.0, 1.0);

    return (cluster_closest_z + 0.001 >= ocl_furthest_z);
}

// ============================================================================
// MAIN COMPUTE DISPATCH (1 THREAD POR INSTÂNCIA — 1 DISPATCH PARA TODA A CENA)
// ============================================================================

void main() {
    uint inst_idx = gl_GlobalInvocationID.x;
    if (inst_idx >= ubo.count_params.x) {
        return; // Fora do intervalo de instâncias da cena
    }

    GPUInstanceData inst = instances[inst_idx];

    // 1. Verificação de Visibilidade Básica
    if ((inst.visibility_flags & 1u) == 0u) {
        return; // Instância explicitamente invisível
    }

    // 2. Frustum Culling em Nível de Instância
    if (ubo.count_params.z != 0u) {
        if (!ARB_GPU_TestFrustum(inst.bounding_sphere.xyz, inst.bounding_sphere.w)) {
            return; // Instância totalmente fora do frustum da câmera
        }
    }

    // 3. Hi-Z Occlusion Culling em Nível de Instância
    if (ubo.render_params.y != 0u) {
        if (!ARB_GPU_TestHiZOcclusion(inst.bounding_sphere.xyz, inst.bounding_sphere.w)) {
            return; // Instância ocluída pelo buffer de profundidade
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
        // LOD FORÇADO: Apenas clusters do nível requisitado
        uint forced_lod = uint(inst.material_metal_spec.w);
        for (uint i = 0u; i < inst.cluster_count; ++i) {
            uint global_cluster_idx = inst.cluster_offset + i;
            GPUCluster c = clusters[global_cluster_idx];
            if (c.cluster_info.y == forced_lod) {
                atomicAdd(total_clusters_evaluated, 1u);

                vec3 world_center = (inst.model_matrix * vec4(c.center_radius.xyz, 1.0)).xyz;
                float world_radius = c.center_radius.w * max_scale;

                bool visible = true;
                if (ubo.count_params.z != 0u) {
                    visible = ARB_GPU_TestFrustum(world_center, world_radius);
                }
                if (visible && ubo.count_params.w != 0u) {
                    vec3 world_cone_axis = normalize(mat3(inst.normal_matrix) * c.cone_axis_cutoff.xyz);
                    if ((inst.visibility_flags & 4u) != 0u) world_cone_axis = -world_cone_axis;
                    visible = ARB_GPU_TestConeCull(world_center, world_radius, world_cone_axis, c.cone_axis_cutoff.w);
                }
                if (visible && ubo.render_params.y != 0u) {
                    visible = ARB_GPU_TestHiZOcclusion(world_center, world_radius);
                }

                if (visible) {
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
        }
    } else {
        // ====================================================================
        // HIERARCHICAL TOP-DOWN DAG CULLING COM EARLY-OUT
        // Começa do nível mais grosseiro (raiz da árvore) descendo até LOD 0.
        // Se um nível satisfaz a tolerância de erro de tela,
        // seleciona os clusters e INTERROMPE (Early-Out) a descida!
        // ====================================================================
        uint max_lod = (inst.lod_count > 0u) ? (inst.lod_count - 1u) : 0u;

        for (int current_lod = int(max_lod); current_lod >= 0; --current_lod) {
            bool any_selected_at_this_lod = false;

            for (uint i = 0u; i < inst.cluster_count; ++i) {
                uint global_cluster_idx = inst.cluster_offset + i;
                GPUCluster c = clusters[global_cluster_idx];

                if (int(c.cluster_info.y) == current_lod) {
                    // Avalia cluster deste nível
                    atomicAdd(total_clusters_evaluated, 1u);

                    vec3 world_center = (inst.model_matrix * vec4(c.center_radius.xyz, 1.0)).xyz;
                    float world_radius = c.center_radius.w * max_scale;

                    // Frustum culling do cluster
                    if (ubo.count_params.z != 0u) {
                        if (!ARB_GPU_TestFrustum(world_center, world_radius)) {
                            continue;
                        }
                    }

                    // Erro projetado em pixels do grupo pai na tela e Frustum Culling do Grupo Pai
                    float p_error = c.group_bounds_error.w * max_scale;
                    vec3 p_center_world = (inst.model_matrix * vec4(c.group_bounds_error.xyz, 1.0)).xyz;
                    bool parent_in_frustum = true;
                    if (ubo.count_params.z != 0u) {
                        parent_in_frustum = ARB_GPU_TestFrustum(p_center_world, world_radius);
                    }
                    if (!parent_in_frustum) {
                        continue;
                    }
                    float p_err_px = ARB_GPU_ProjectScreenError(p_center_world, 0.0, p_error, vp_h, fov_factor);

                    // Condição de aceitação: erro na tela <= max_screen_err OU estamos na base (LOD 0)
                    if (p_err_px <= max_screen_err || current_lod == 0) {
                        // Backface cone culling
                        bool visible = true;
                        if (ubo.count_params.w != 0u) {
                            vec3 world_cone_axis = normalize(mat3(inst.normal_matrix) * c.cone_axis_cutoff.xyz);
                            if ((inst.visibility_flags & 4u) != 0u) world_cone_axis = -world_cone_axis;
                            visible = ARB_GPU_TestConeCull(world_center, world_radius, world_cone_axis, c.cone_axis_cutoff.w);
                        }

                        // Hi-Z Occlusion culling
                        if (visible && ubo.render_params.y != 0u) {
                            visible = ARB_GPU_TestHiZOcclusion(world_center, world_radius);
                        }

                        if (visible) {
                            uint slot = atomicAdd(instance_count, 1u);
                            if (slot < max_capacity) {
                                visible_items[slot].instance_id = inst_idx;
                                visible_items[slot].cluster_id = global_cluster_idx;
                                atomicAdd(total_triangles_drawn, c.data_offsets.w);
                            } else {
                                overflow_flag = 1u;
                            }
                        }
                        any_selected_at_this_lod = true;
                    }
                }
            }

            // EARLY-OUT: Se este nível hierárquico atendeu à fidelidade visual exigida,
            // PARADA ANTECIPADA! Não avalia os clusters dos níveis filhos mais densos.
            if (any_selected_at_this_lod) {
                break;
            }
        }
    }
}
