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
} ubo;

// 4: Imagem de saida 2D para amostragem no Vertex Shader (Texture2DRD)
layout(set = 0, binding = 4, rgba32f) uniform writeonly image2D out_selection_image;

bool test_frustum(vec3 center, float radius) {
    for (int i = 0; i < 6; ++i) {
        if (dot(ubo.frustum_planes[i].xyz, center) + ubo.frustum_planes[i].w < -radius) {
            return false;
        }
    }
    return true;
}

bool test_backface(vec3 center, float radius, vec3 cone_axis, float cutoff) {
    if (cutoff >= 1.0) return true; // Cones com cutoff >= 1 nao podem ser descartados
    vec3 c_to_cam = center - ubo.camera_pos_fov.xyz;
    float dist = length(c_to_cam);
    // meshoptimizer: rejeita quando dot(center - camera_pos, cone_axis) >= cutoff * dist + radius
    return dot(c_to_cam, cone_axis) < (cutoff * dist + radius);
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
        if (!test_frustum(center, radius)) {
            return;
        }
    }

    // 2. Normal Cone Backface Culling
    if (ubo.count_params.w != 0u) {
        if (!test_backface(center, radius, c.cone_axis_cutoff.xyz, c.cone_axis_cutoff.w)) {
            return;
        }
    }

    // 3. Selecao Hierarquica de LOD (DAG Nanite-style ou Manual)
    bool is_selected = false;
    uint lod_mode = uint(ubo.viewport_params.w);

    if (lod_mode == 1u) {
        // Modo Forcado: Desenha apenas o nivel de LOD selecionado manualmente
        if (c.cluster_info.y == ubo.count_params.y) {
            is_selected = true;
        }
    } else {
        // Modo DAG Automatico por Projecao de Erro em Pixels
        float fov_factor = max(ubo.camera_pos_fov.w, 0.1);
        float vp_h = max(ubo.viewport_params.y, 1.0);
        float max_screen_err = max(ubo.viewport_params.z, 0.1);

        // A. Erro do Grupo Pai (deve ser MAIOR que o limiar para nao podermos simplificar)
        vec3 p_center = c.group_bounds_error.xyz;
        float p_error = c.group_bounds_error.w;

        float p_dist = max(distance(ubo.camera_pos_fov.xyz, p_center) - radius, 0.01);
        float p_err_pixels = (p_error * vp_h) / (2.0 * p_dist * fov_factor);

        // B. Erro do Grupo Filho Refinado (se houver, deve ser MENOR OU IGUAL ao limiar para nao precisarmos dele)
        bool child_satisfied = true;
        int refined_group_id = int(c.cluster_info.w);
        if (refined_group_id >= 0) {
            vec3 r_center = c.refined_bounds_error.xyz;
            float r_error = c.refined_bounds_error.w;
            float r_dist = max(distance(ubo.camera_pos_fov.xyz, r_center) - radius, 0.01);
            float r_err_pixels = (r_error * vp_h) / (2.0 * r_dist * fov_factor);
            child_satisfied = (r_err_pixels <= max_screen_err);
        }

        // Se o grupo pai tiver erro suficiente para exigir este detalhe,
        // e o grupo filho for detalhado demais para ser necessario:
        // OU se for o grupo mais grosso (erro infinito / muito alto):
        bool parent_needed = (p_err_pixels > max_screen_err) || (p_error > 10000.0);
        is_selected = parent_needed && child_satisfied;
    }

    if (is_selected) {
        // Incrementa atomicamente o contador de instancias do VkDrawIndirectCommand
        uint slot = atomicAdd(instance_count, 1u);
        visible_cluster_ids[slot] = g_idx;
        atomicAdd(total_triangles_drawn, c.data_offsets.w);

        // Escreve na textura 2D para amostragem sem latencia pelo Vertex Shader
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
