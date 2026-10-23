#[compute]
#version 450

// ARBORIA VIRTUAL GEOMETRY — GPU CLUSTER CULLING & DAG LOD SELECTION
// 100% Vulkan Compute Pipeline para Godot 4.3+

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

struct GPUCluster {
    vec4 center_radius;        // xyz = center, w = radius
    vec4 cone_axis_cutoff;     // xyz = normal cone axis, w = cutoff
    vec4 group_bounds_error;   // xyz = parent group center, w = parent group error
    vec4 refined_bounds_error; // xyz = refined group center, w = refined group error (-1.0 if base LOD)
    uvec4 data_offsets;        // x = vertex_offset, y = vertex_count, z = triangle_offset, w = triangle_count
    uvec4 cluster_info;        // x = cluster_id, y = lod_level, z = group_id, w = refined_group
};

// 0: Buffer de metadados de todos os clusters da malha
layout(set = 0, binding = 0, std430) readonly buffer InClusters {
    GPUCluster clusters[];
};

// 1: Buffer compacto de saida com IDs dos clusters visiveis
layout(set = 0, binding = 1, std430) writeonly buffer OutVisibleClusters {
    uint visible_cluster_ids[];
};

// 2: Buffer de argumentos de desenho indireto (VkDrawIndirectCommand) e telemetria
layout(set = 0, binding = 2, std430) buffer OutCounterAndDrawArgs {
    uint vertex_count;              // offset 0: 384 (128 triangulos * 3 vertices)
    uint instance_count;            // offset 4: Quantidade de clusters visiveis (atualizado via atomicAdd diretamente!)
    uint first_vertex;              // offset 8: 0
    uint first_instance;            // offset 12: 0
    uint total_triangles_drawn;     // offset 16: Contador de triangulos desenhados
    uint total_clusters_evaluated;  // offset 20: Total de clusters processados
};

// 3: Uniforms de camera e configuracoes de culling
layout(set = 0, binding = 3, std140) uniform CameraUniforms {
    mat4 view_proj;
    vec4 frustum_planes[6];
    vec4 camera_pos_fov;   // xyz = camera_pos, w = fov_factor
    vec4 viewport_params;  // x = viewport_width, y = viewport_height, z = max_screen_error_pixels, w = lod_mode (0 = auto DAG, 1 = force LOD)
    uvec4 count_params;    // x = total_clusters, y = forced_lod_level, z = enable_frustum_culling, w = enable_cone_culling
    uvec4 render_params;   // x = shading_mode (0 = unshaded, 1 = normal, 2 = lit, 3 = cluster debug)
} ubo;

// 4: Imagem de saida 2D para amostragem no Vertex Shader (Texture2DRD)
layout(set = 0, binding = 4, rgba32f) uniform writeonly image2D out_selection_image;

// 5: Pirâmide de profundidade Hierárquica Hi-Z para descarte de oclusão
layout(set = 0, binding = 5) uniform sampler2D hiz_depth_pyramid;

// ============================================================================
// ARBORIA ENGINE — FORMULAÇÃO MATEMÁTICA RASTREADA (ARB-MATH-V7-2026)
// Referências: NVIDIA vk_lod_clusters, Scthe/nanite-webgpu, zeux/meshoptimizer
// ============================================================================

// [ARB_MATH_01] Teste de Frustum Culling contra os 6 planos da câmera
bool ARB_GPU_TestFrustum(vec3 center, float radius) {
    for (int i = 0; i < 6; ++i) {
        if (dot(ubo.frustum_planes[i].xyz, center) + ubo.frustum_planes[i].w < -radius) {
            return false;
        }
    }
    return true;
}

// [ARB_MATH_02] Teste de Backface Cone Culling (NVIDIA/Meshoptimizer)
bool ARB_GPU_TestConeCull(vec3 center, float radius, vec3 cone_axis, float cutoff) {
    if (cutoff >= 1.0) return true; // Cones com cutoff >= 1 cobrem toda a esfera
    vec3 c_to_cam = center - ubo.camera_pos_fov.xyz;
    float dist = length(c_to_cam);
    return dot(c_to_cam, cone_axis) < (cutoff * dist + radius);
}

// [ARB_MATH_03] Projeção de Erro de Espaço de Objeto para Pixels na Tela (Nanite/NVIDIA)
float ARB_GPU_ProjectScreenError(vec3 center, float radius, float mesh_error, float vp_height, float fov_factor) {
    float dist = length(center - ubo.camera_pos_fov.xyz);
    // Distância efetiva à borda da esfera delimitadora (evita singularidades dentro da esfera)
    float d_eff = max(dist - radius, 0.05);
    return (mesh_error * vp_height) / (2.0 * d_eff * fov_factor);
}

// [ARB_MATH_04] Critério Dual de Corte da DAG (Nanite Cut-Condition)
bool ARB_GPU_EvaluateDAGCut(
    vec3 p_center, float p_error,
    vec3 r_center, float r_error, int refined_group_id,
    float vp_height, float fov_factor, float max_screen_err
) {
    // 1. Condição do Grupo Pai (Parent): Deve exigir detalhe nesta distância
    bool parent_needed;
    if (p_error > 10000.0) {
        parent_needed = true; // Raiz da árvore (LOD 0)
    } else {
        float p_err_px = ARB_GPU_ProjectScreenError(p_center, 0.0, p_error, vp_height, fov_factor);
        parent_needed = (p_err_px > max_screen_err);
    }

    // 2. Condição do Grupo Filho (Refined): Deve ser dispensável nesta distância
    bool child_satisfied = true;
    if (refined_group_id >= 0) {
        float r_err_px = ARB_GPU_ProjectScreenError(r_center, 0.0, r_error, vp_height, fov_factor);
        child_satisfied = (r_err_px <= max_screen_err);
    }

    // Apenas seleciona se o pai precisa deste nível e o filho não é necessário
    return parent_needed && child_satisfied;
}

// [ARB_MATH_05] Teste de Oclusão Hi-Z Hierárquico em Reversed-Z (Vulkan 1.4)
bool ARB_GPU_TestHiZOcclusion(vec3 center, float radius) {
    vec4 clip_center = ubo.view_proj * vec4(center, 1.0);
    if (clip_center.w <= 0.0) return true; // Near clip guard

    vec2 vp = ubo.viewport_params.xy;
    float proj_radius = (radius / clip_center.w) * (vp.y * 0.5 * ubo.camera_pos_fov.w);
    vec2 ndc = clip_center.xy / clip_center.w;
    vec2 screen_pos = (ndc * 0.5 + 0.5) * vp;

    vec2 bbox_min = clamp(screen_pos - vec2(proj_radius), vec2(0.0), vp);
    vec2 bbox_max = clamp(screen_pos + vec2(proj_radius), vec2(0.0), vp);
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
    vec3 c_to_cam = ubo.camera_pos_fov.xyz - center;
    float dist = length(c_to_cam);
    vec3 closest_pt = center + (c_to_cam / max(dist, 0.001)) * min(radius, dist * 0.9);
    vec4 clip_closest = ubo.view_proj * vec4(closest_pt, 1.0);
    if (clip_closest.w <= 0.0) return true;
    float cluster_closest_z = clamp(clip_closest.z / clip_closest.w, 0.0, 1.0);

    // Em Reversed-Z: se o ponto mais próximo do cluster for menor que a profundidade oclusora,
    // o cluster está totalmente atrás e é ocluído
    return (cluster_closest_z >= ocl_furthest_z);
}

void main() {
    uint g_idx = gl_GlobalInvocationID.x;
    if (g_idx >= ubo.count_params.x) return;

    atomicAdd(total_clusters_evaluated, 1u);

    GPUCluster c = clusters[g_idx];
    vec3 center = c.center_radius.xyz;
    float radius = c.center_radius.w;

    // 1. Frustum Culling
    if (ubo.count_params.z != 0u) {
        if (!ARB_GPU_TestFrustum(center, radius)) {
            return;
        }
    }

    // 2. Normal Cone Backface Culling
    if (ubo.count_params.w != 0u) {
        if (!ARB_GPU_TestConeCull(center, radius, c.cone_axis_cutoff.xyz, c.cone_axis_cutoff.w)) {
            return;
        }
    }

    // 3. Hi-Z Occlusion Culling (Descarte de Geometria Oculta por Reversed-Z)
    if (ubo.render_params.y != 0u) {
        if (!ARB_GPU_TestHiZOcclusion(center, radius)) {
            return;
        }
    }

    // 4. Seleção Hierárquica de LOD (DAG Nanite-style ou Manual)
    bool is_selected = false;
    uint lod_mode = uint(ubo.viewport_params.w);

    if (lod_mode == 1u) {
        // Modo Forçado: Desenha apenas o nível de LOD solicitado manualmente
        if (c.cluster_info.y == ubo.count_params.y) {
            is_selected = true;
        }
    } else {
        // Modo DAG Automático por Projeção Perspectiva de Erro (ARB-MATH-04)
        float fov_factor = max(ubo.camera_pos_fov.w, 0.1);
        float vp_h = max(ubo.viewport_params.y, 1.0);
        float max_screen_err = max(ubo.viewport_params.z, 0.1);

        is_selected = ARB_GPU_EvaluateDAGCut(
            c.group_bounds_error.xyz, c.group_bounds_error.w,
            c.refined_bounds_error.xyz, c.refined_bounds_error.w, int(c.cluster_info.w),
            vp_h, fov_factor, max_screen_err
        );
    }

    if (is_selected) {
        // Incrementa atomicamente o contador de instâncias do VkDrawIndirectCommand
        uint slot = atomicAdd(instance_count, 1u);
        if (slot < ubo.count_params.x) {
            visible_cluster_ids[slot] = g_idx;
            atomicAdd(total_triangles_drawn, c.data_offsets.w);

            // Escreve na textura 2D para amostragem sem latência pelo Vertex Shader
            ivec2 tex_coord = ivec2(int(slot % 2048u), int(slot / 2048u));
            vec4 pixel_data = vec4(
                float(g_idx),               // x = ID do cluster global
                float(c.data_offsets.y),    // y = vertex_count
                float(c.data_offsets.w),    // z = triangle_count
                float(c.cluster_info.y)     // w = lod_level
            );
            imageStore(out_selection_image, tex_coord, pixel_data);
        }
    }
}
